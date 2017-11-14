module GraphqlModelMapper
    module Resolve
        def self.query_resolver(obj, args, ctx, name)
            obj_context = name.classify.constantize
            select_args = args[:select] || args
        
            if !GraphqlModelMapper.authorized?(ctx, obj_context.name, :query)
              raise GraphQL::ExecutionError.new("error: unauthorized access: #{:query} '#{obj_context.class_name.classify}'")
            end
            classmethods = []
            scope_allowed = false
            with_deleted_allowed = false
            if select_args[:scope]
              classmethods = obj_context.methods - Object.methods
              scope_allowed = classmethods.include?(select_args[:scope].to_sym)
              raise GraphQL::ExecutionError.new("error: invalid scope '#{select_args[:scope]}' specified, '#{select_args[:scope]}' method does not exist on '#{ctx.field.name.classify}'") unless scope_allowed
            end
            if select_args[:with_deleted]
              classmethods = obj_context.methods - Object.methods
              with_deleted_allowed = classmethods.include?(:with_deleted)
              raise GraphQL::ExecutionError.new("error: invalid usage of 'with_deleted', 'with_deleted' method does not exist on '#{ctx.field.name.classify}'") unless with_deleted_allowed
            end

            implied_includes = self.get_implied_includes(name.classify.constantize, ctx.ast_node)

            if !implied_includes.empty? 
              obj_context = obj_context.includes(implied_includes)
              if Rails.version.split(".").first.to_i > 3
                obj_context = obj_context.references(implied_includes)
              end
            end
            if select_args[:ids]
                obj_context = obj_context.where(["#{obj_context.model_name.plural}.id in (?)", select_args[:ids]])
            end
            if select_args[:id]
              obj_context = obj_context.where(["#{obj_context.model_name.plural}.id = ?", select_args[:id].to_i])
            end
            if select_args[:where]
              obj_context = obj_context.where(select_args[:where])
            end
            if with_deleted_allowed
              obj_context = obj_context.with_deleted
            end
            if scope_allowed
              obj_context = obj_context.send(select_args[:scope].to_sym)
            end
            if !select_args[:limit].nil? && select_args[:limit].to_f > 0
              obj_context = obj_context.limit(select_args[:limit])
            end
            if select_args[:offset]
              obj_context = obj_context.offset(select_args[:offset])
            end
            if select_args[:order]
              obj_context = obj_context.order(select_args[:order])
            end
            if select_args[:explain]
              obj_context = obj_context.eager_load(implied_includes)
              raise GraphQL::ExecutionError.new(obj_context.explain.split("\n").first.sub("EXPLAIN for: ", ""))
            end
            obj_context
        end

        def self.update_resolver(obj, inputs, ctx, name)
            item = GraphqlModelMapper::Resolve.nested_update(ctx, name, inputs)
            item
        end
        
        def self.delete_resolver(obj, inputs, ctx, model_name)
            model = model_name.classify.constantize
            items = self.query_resolver(obj, inputs, ctx, model_name)
            ids = items.collect(&:id)
            if !GraphqlModelMapper.authorized?(ctx, model_name, :update)
                raise GraphQL::ExecutionError.new("error: unauthorized access: delete '#{model_name.classify}', transaction cancelled")
            end    
            begin
                deleted_items = model.delete(ids)
            rescue => e
                raise e #GraphQL::ExecutionError.new("error: delete")
            end
            if model.methods.include?(:with_deleted)
                items.with_deleted
            else
                items
            end
        end

        def self.create_resolver(obj, inputs, ctx, model_name)
            if !GraphqlModelMapper.authorized?(ctx, model_name, :create)
                raise GraphQL::ExecutionError.new("error: unauthorized access: create '#{model_name.classify}'")
            end
            model = model_name.classify.constantize   
            item = model.new(inputs[model_name.downcase].to_h)
            begin
              if !item.valid?
                raise GraphQL::ExecutionError.new(item.errors.full_messages.join("; "))
              else
                raise GraphQL::ExecutionError.new("error: WIP, item not saved but is a valid '#{model_name.classify}'")
                #item.save!
              end
            end
            item
        end

          def self.using_relay_pagination?(selection)
          selection.name == 'edges'
        end
    
        def self.using_is_items_collection?(selection)
          selection.name == 'items'
        end

        def self.using_nodes_pagination?(selection)
          selection.name == 'nodes'
        end

        def self.has_reflection_with_name?(class_name, selection_name)
          class_name.reflect_on_all_associations.select{|m|m.name == selection_name.to_sym}.present?
        end

        def self.map_relay_pagination_depencies(class_name, selection, dependencies)
          node_selection = selection.selections.find { |sel| sel.name == 'node' }
    
          if node_selection.present?
            get_implied_includes(class_name, node_selection, dependencies)
          else
            dependencies
          end
        end

        def self.get_implied_includes(class_name, ast_node, dependencies={})
          ast_node.selections.each do |selection|
            name = selection.name
    
            if using_relay_pagination?(selection)
              map_relay_pagination_depencies(class_name, selection, dependencies)
              next
            end
    
            if using_nodes_pagination?(selection)
              get_implied_includes(class_name, selection, dependencies)
              next
            end

            if using_is_items_collection?(selection)
              get_implied_includes(class_name, selection, dependencies)
              next
            end
    
            if has_reflection_with_name?(class_name, name)
              begin
                current_class_name = selection.name.singularize.classify.constantize
                dependencies[name] = get_implied_includes(current_class_name, selection)
              rescue NameError
                selection_name = class_name.reflections.with_indifferent_access[selection.name].options[:class_name]
                current_class_name = selection_name.singularize.classify.constantize
                dependencies[selection.name.to_sym] = get_implied_includes(current_class_name, selection)
                next
              end
            end
          end
          dependencies
        end
    

        def self.nested_update(ctx, model_name, inputs, child_name=nil, child_id=nil, parent_name=nil, parent_id=nil, klass_name=nil)
            model = model_name.classify.constantize
            
            if !child_name.nil? && !child_id.nil? # has_many && has_one
              inputs_root = inputs
              #puts "inputs_root[:id] #{inputs_root[:id]} #{inputs_root}"
              if model.public_methods.include?(:with_deleted)
                item = model.with_deleted.where("id = ? and #{child_name.downcase}_id = ?", inputs_root[:id], child_id).first
              else
                item = model.where("id = ? and #{child_name.downcase}_id = ?", inputs_root[:id], child_id).first
              end
              raise GraphQL::ExecutionError.new("error: #{model.name} record not found for #{model.name}.id = #{inputs_root[:id]} and #{model.name}.#{child_name.downcase}_id = #{child_id}") if item.nil?
            elsif !parent_name.nil? && !parent_id.nil? # belongs_to
              inputs_root = inputs
              #puts "parent_id #{parent_id} parent_name #{parent_name} #{model_name} model.with_deleted.find(#{parent_id}).send(#{parent_name}.to_sym).id} inputs_root[:id] #{inputs_root[:id]} #{inputs_root}"
              if model.public_methods.include?(:with_deleted)
                item = model.with_deleted.find(parent_id).public_send(parent_name.to_sym) if model.with_deleted.find(parent_id).public_send(parent_name.to_sym) && model.with_deleted.find(parent_id).public_send(parent_name.to_sym).id == inputs_root[:id]
              else
                item = model.find(parent_id).public_send(parent_name.to_sym) if model.find(parent_id).public_send(parent_name.to_sym) && model.with_deleted.find(parent_id).public_send(parent_name.to_sym).id == inputs_root[:id]
              end
              raise GraphQL::ExecutionError.new("error: #{model.name}.#{parent_name} record not found for  #{model.name}.with_deleted.find(#{parent_id}).#{parent_name}_id = #{inputs_root[:id]}") if item.nil?
              model_name = klass_name
              model = klass_name.classify.constantize
            else #root query always single record, need to offeset property for object_input_type
              inputs_root = inputs[model_name.downcase]
              #puts "inputs_root[:id] #{inputs_root[:id]} #{inputs_root}"
              if model.public_methods.include?(:with_deleted)
                item = model.with_deleted.find(inputs_root[:id])
              else
                item = model.find(inputs_root[:id])
              end
              raise GraphQL::ExecutionError.new("error: #{model.name} record not found for #{model.name}.id=#{inputs[model_name.downcase][:id]}") if item.nil?
            end
            if !GraphqlModelMapper.authorized?(ctx, model.name, :update)
              raise GraphQL::ExecutionError.new("error: unauthorized access: #{:update} '#{model}', transaction cancelled")
            end
        
            item_associations = model.reflect_on_all_associations.select{|t| begin t.klass rescue next end}.select{|t| !t.options[:polymorphic]}
            item_association_names = item_associations.map{|m| m.name.to_s}
            input_association_names = item_association_names & inputs_root.to_h.keys
            
            item.transaction do
              #puts "***********item.update_attributes(#{inputs_root.to_h.except('id').except!(*item_association_names)})"
              #puts "***********ctx[current_user.to_sym].is_admin?(#{ctx[:current_user].is_admin?})"
              item.update_attributes(inputs_root.to_h.except('id').except!(*item_association_names))
              input_association_names.each do |ia|
                lclinput = inputs_root[ia]
                ass = item_associations.select{|a| a.name.to_s == ia}.first
                klass = ass.klass
                is_collection = ass.collection?
                belongs_to = ass.belongs_to?
                #puts "#{ass.name} #{ass.collection?} #{ass.belongs_to?}"
                #puts "#{ass.association_foreign_key} #{ass.association_primary_key} #{ass.active_record_primary_key}"
                
                if is_collection
                  #puts "is_collection"
                  lclinput.each do |i|
                    #puts "#{klass.name}  #{i.to_h}  #{model_name.downcase} #{inputs_root[:id]}"
                    GraphqlModelMapper::Resolve.nested_update(ctx, klass.name, i, model_name.downcase, inputs_root[:id])
                  end
                elsif !is_collection && belongs_to
                  #puts "belongs_to"
                  #puts "self.nested_update(#{ctx}, #{model.name}, #{lclinput.to_h}, nil, nil, #{ass.name}, #{inputs_root[:id]}, #{klass.name})"
                  GraphqlModelMapper::Resolve.nested_update(ctx, model.name, lclinput, nil, nil, ass.name, inputs_root[:id], klass.name)
                elsif !is_collection && !belongs_to #has_one
                  #puts "has_one"
                  #puts "self.nested_update(#{ctx}, #{klass.name}, #{lclinput.to_h}, #{model_name.downcase}, #{inputs_root[:id]})"
                  GraphqlModelMapper::Resolve.nested_update(ctx, model.name, lclinput, nil, nil, ass.name, inputs_root[:id], klass.name)
                end
              end
            end
            item
          end                
    end
end    