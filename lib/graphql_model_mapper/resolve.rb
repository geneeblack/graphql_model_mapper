require 'search_object/plugin/graphql'

module GraphqlModelMapper
  module Resolve
    def self.query_resolver(obj, args, ctx, name)
        
        if obj && obj.class.name != name
          reflection = obj.class.name.classify.constantize.reflect_on_all_associations.select{|k| k.name == ctx.ast_node.name.to_sym}.first
          model = reflection.klass
          obj_context = obj.send(reflection.name)
          select_args = args[:select] || args
          select_args = select_args.to_h.with_indifferent_access
          #binding.pry
          if ctx[:root_args] && ctx[:root_args][:full_filter] && ctx[:root_args][:full_filter][reflection.name.to_sym]
            select_args[:full_filter] = ctx[:root_args][:full_filter][reflection.name.to_sym].to_h.with_indifferent_access.deep_merge(select_args[:full_filter].to_h.with_indifferent_access) 
          end
          ctx[:root_args] = select_args
        else
          obj_context = name.classify.constantize
          select_args = args[:select] || args
          #binding.pry
          ctx[:root_args] = select_args
          select_args = select_args.to_h.with_indifferent_access
          model = obj_context
        end
        

        # return obj_context if select_args.empty?
        #return obj_context if select_args.keys.select{|m| !select_args[m].nil?}.length == 0 
          

    
        if !GraphqlModelMapper.authorized?(ctx, obj_context.name, :query) && GraphqlModelMapper.use_graphql_object_restriction
          raise GraphQL::ExecutionError.new("error: unauthorized access: #{:query} '#{obj_context.class_name.classify}'")
        end
        classmethods = []
        scope_allowed = false
        with_deleted_allowed = false
        test_query = false


        if select_args[:scopes]
          input_scopes = select_args[:scopes]
          allowed_scopes = []
          input_scopes.each do |s|
            if model.public_methods.include?(s[:scope].to_sym)
              allowed_scopes << {method: s[:scope].to_sym, args: s[:arguments] }
            else
              next
            end
          end
          errors = []
          allowed_scopes.each do |a|
            begin
             obj_context = obj_context.send(a[:method], *a[:args])
            rescue => e
              errors << "scope method: #{a[:method]} arguments: #{a[:args] || []} error: #{e.message}"
            end
          end
          if errors.length > 0
            raise GraphQL::ExecutionError.new(errors.join("; "))
          end
        end
        if select_args[:scope]
          scope_allowed = model.public_methods.include?(select_args[:scope].to_sym)
          raise GraphQL::ExecutionError.new("error: invalid scope '#{select_args[:scope]}' specified, '#{select_args[:scope]}' method does not exist on '#{obj_context.class_name.classify}'") unless scope_allowed
        end
        if select_args[:with_deleted]
          with_deleted_allowed = model.public_methods.include?(:with_deleted)
          raise GraphQL::ExecutionError.new("error: invalid usage of 'with_deleted', 'with_deleted' method does not exist on '#{obj_context.class_name.classify}'") unless with_deleted_allowed
        end
        if with_deleted_allowed && select_args[:with_deleted]
          obj_context = obj_context.send(:with_deleted)
        end

        implied_includes = ""
        if select_args[:where] || select_args[:order] || select_args[:short_filter] || select_args[:full_filter]
          implied_includes = self.get_implied_includes(obj_context.name.classify.constantize, ctx.ast_node)
          if select_args[:full_filter]
            test = self.get_filter_implied_includes(select_args[:full_filter].to_h, parent={})
            implied_includes = implied_includes.merge(test)
          end
          if !implied_includes.empty? 
            obj_context = obj_context.includes(implied_includes)
            ##binding.pry
            if Rails.version.split(".").first.to_i > 3
              obj_context = obj_context.references(implied_includes)
            end
          end
        end
        if select_args[:id]
          type_name, item_id = nil
          begin
            type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(GraphqlModelMapper::Encryption.decode(select_args[:id]))
          rescue => e
            raise GraphQL::ExecutionError.new("incorrect global id: unable to resolve id: #{e.message}")
          end
          raise GraphQL::ExecutionError.new("incorrect global id: unable to resolve type for id:'#{select_args[:id]}'") if type_name.nil?
          model_name = GraphqlModelMapper.get_constant(type_name.upcase).metadata[:model_name].to_s.classify
          raise GraphQL::ExecutionError.new("incorrect global id '#{select_args[:id]}': expected global id for '#{name}', received global id for '#{model_name}'") if model_name != name 
          obj_context = obj_context.where(["#{obj_context.model_name.plural}.id = ?", item_id.to_i])
        end
        if select_args[:ids]
          finder_array = []
          errors = []
          select_args[:ids].each do |id|
            type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(GraphqlModelMapper::Encryption.decode(id))
            if type_name.nil?
              errors << "incorrect global id: unable to resolve type for id:'#{id}'"
              next
            end
            model_name = GraphqlModelMapper.get_constant(type_name.upcase).metadata[:model_name].to_s.classify
            if model_name != name 
              errors << "incorrect global id '#{id}': expected global id for '#{name}', received global id for '#{model_name}'"
              next
            end
            finder_array << item_id.to_i
          end
          if errors.length > 0
            raise GraphQL::ExecutionError.new(errors.join(";")) 
          end
          obj_context = obj_context.where(["`#{obj_context.model_name.plural}`.id in (?)", finder_array])
        end
        if select_args[:item_ids]
          obj_context = obj_context.where(["`#{obj_context.model_name.plural}`.id in (?)", select_args[:item_ids]])
        end
        if select_args[:item_id]
          obj_context = obj_context.where(["`#{obj_context.model_name.plural}`.id = ?", select_args[:item_id].to_i])
        end
        if select_args[:where]
          begin
          obj_context = obj_context.where(select_args[:where])
          rescue => e
            raise GraphQL::ExecutionError.new("#{e.message}: #{select_args[:where]}")
            
          end
          test_query = true
        else
          obj_context = obj_context.where("1=1")
        end
        if select_args[:short_filter]
          obj_context = self.apply_short_filter(obj_context, select_args[:short_filter])
        end
        if select_args[:full_filter]
          #binding.pry

          @aliases = ctx[:table_aliases] = []
          obj_context = self.apply_full_filter_with_aliases(obj_context, select_args[:full_filter].to_h.deep_merge(implied_includes), model.name.pluralize.downcase) #.to_h.merge(implied_includes)
        end

        if scope_allowed
          obj_context = obj_context.send(select_args[:scope].to_sym)
        end
        if select_args[:order]
          obj_context = obj_context.order(select_args[:order])
          test_query = true
        end
        #check for sql errors
        begin
          GraphqlModelMapper.logger.info "GraphqlModelMapper: ****** testing query for validity"
          test_statement = obj_context.includes(implied_includes)
          if Rails.version.split(".").first.to_i > 3
            test_statement = test_statement.references(implied_includes)
          end
          test_result = test_statement.limit(0).to_a

        rescue ActiveRecord::StatementInvalid =>  e
            raise GraphQL::ExecutionError.new(e.message.sub(" AND (1=1)", "").sub(" LIMIT 0", ""))
        end if test_query
        if select_args[:explain]
          obj_context = obj_context.limit(1)
          obj_context = obj_context.eager_load(implied_includes)
          err = nil
          begin
            #err = GraphQL::ExecutionError.new(obj_context.explain.split("\n").first.sub("EXPLAIN for: ", "").sub(" LIMIT 1", !select_args[:limit].nil? && select_args[:limit].to_f > 0 ? "LIMIT #{select_args[:limit]}" : "").sub(" AND (1=1)","").sub(" WHERE (1=1)",""))
            err = GraphQL::ExecutionError.new(obj_context.explain.split("EXPLAIN for:").last.split("\n").first.sub("EXPLAIN for: ", "").sub(" LIMIT 1", !select_args[:limit].nil? && select_args[:limit].to_f > 0 ? "LIMIT #{select_args[:limit]}" : "").sub(" AND (1=1)","").sub(" WHERE (1=1)",""))
          rescue 
            err =  GraphQL::ExecutionError.new(obj_context.to_sql.sub("EXPLAIN for: ", "").sub(" LIMIT 1", !select_args[:limit].nil? && select_args[:limit].to_f > 0 ? "LIMIT #{select_args[:limit]}" : "").sub(" AND (1=1)","").sub(" WHERE (1=1)",""))
          end
          raise err if !err.nil?
        end
        #if select_args[:limit].nil?
        #    obj_context = obj_context.limit(GraphqlModelMapper.max_page_size+1)
        #end
        ##binding.pry
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
        if !GraphqlModelMapper.authorized?(ctx, model_name, :update) && GraphqlModelMapper.use_graphql_object_restriction
            raise GraphQL::ExecutionError.new("error: unauthorized access: delete '#{model_name.classify}', transaction cancelled")
        end    
        begin
            deleted_items = model.delete(ids)
        rescue => e
            raise e #GraphQL::ExecutionError.new("error: delete")
        end
        if model.public_methods.include?(:with_deleted)
            items.with_deleted
        else
            items
        end
    end

    def self.create_resolver(obj, inputs, ctx, model_name)
        if !GraphqlModelMapper.authorized?(ctx, model_name, :create)
            raise GraphQL::ExecutionError.new("error: unauthorized access: create '#{model_name.classify}'") && GraphqlModelMapper.use_graphql_object_restriction
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

    def self.using_items_pagination?(selection)
      selection.name == 'items'
    end

    def self.has_reflection_with_name?(class_name, selection_name)
      class_name.reflect_on_all_associations.select{|m|m.name == selection_name.to_sym}.present?
    end

    def self.map_relay_pagination_depencies(class_name, selection, dependencies)
      node_selection = selection.selections.find { |sel| sel.name == 'node' }

      if node_selection.present?
        self.get_implied_includes(class_name, node_selection, dependencies)
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
          self.get_implied_includes(class_name, selection, dependencies)
          next
        end

        if using_items_pagination?(selection)
          self.get_implied_includes(class_name, selection, dependencies)
          next
        end

        if using_is_items_collection?(selection)
          self.get_implied_includes(class_name, selection, dependencies)
          next
        end

        if has_reflection_with_name?(class_name, name)
          begin
            current_class_name = selection.name.singularize.classify.constantize
            dependencies[name] = self.get_implied_includes(current_class_name, selection)
          rescue NameError
            selection_name = class_name.reflections.with_indifferent_access[selection.name].class_name
            begin                  
              current_class_name = selection_name.singularize.classify.constantize
              dependencies[selection.name.to_sym] = self.get_implied_includes(current_class_name, selection)
            rescue
                # this will occur if the relation is polymorphic, since polymorphic associations do not have a class_name
                GraphqlModelMapper.logger.info "implied_includes: #{class_name} could not resolve a class for relation #{selection.name}"
            end
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
        #puts "inputs_root[:item_id] #{inputs_root[:item_id]} #{inputs_root}"
        if model.public_methods.include?(:with_deleted)
          item = model.with_deleted.where("id = ? and #{child_name.downcase}_id = ?", inputs_root[:item_id], child_id).first
        else
          item = model.where("id = ? and #{child_name.downcase}_id = ?", inputs_root[:item_id], child_id).first
        end
        raise GraphQL::ExecutionError.new("error: #{model.name} record not found for #{model.name}.id = #{inputs_root[:item_id]} and #{model.name}.#{child_name.downcase}_id = #{child_id}") if item.nil?
      elsif !parent_name.nil? && !parent_id.nil? # belongs_to
        inputs_root = inputs
        #puts "parent_id #{parent_id} parent_name #{parent_name} #{model_name} model.with_deleted.find(#{parent_id}).send(#{parent_name}.to_sym).id} inputs_root[:item_id] #{inputs_root[:item_id]} #{inputs_root}"
        if model.public_methods.include?(:with_deleted)
          item = model.with_deleted.find(parent_id).public_send(parent_name.to_sym) if model.with_deleted.find(parent_id).public_send(parent_name.to_sym) && model.with_deleted.find(parent_id).public_send(parent_name.to_sym).id == inputs_root[:item_id]
        else
          item = model.find(parent_id).public_send(parent_name.to_sym) if model.find(parent_id).public_send(parent_name.to_sym) && model.with_deleted.find(parent_id).public_send(parent_name.to_sym).id == inputs_root[:item_id]
        end
        raise GraphQL::ExecutionError.new("error: #{model.name}.#{parent_name} record not found for  #{model.name}.with_deleted.find(#{parent_id}).#{parent_name}_id = #{inputs_root[:item_id]}") if item.nil?
        model_name = klass_name
        model = klass_name.classify.constantize
      else #root query always single record, need to offeset property for object_input_type
        inputs_root = inputs[model_name.downcase]
        #puts "inputs_root[:item_id] #{inputs_root[:item_id]} #{inputs_root}"
        if model.public_methods.include?(:with_deleted)
          item = model.with_deleted.find(inputs_root[:item_id])
        else
          item = model.find(inputs_root[:item_id])
        end
        raise GraphQL::ExecutionError.new("error: #{model.name} record not found for #{model.name}.id=#{inputs[model_name.downcase][:item_id]}") if item.nil?
      end
      if !GraphqlModelMapper.authorized?(ctx, model.name, :update) && GraphqlModelMapper.use_graphql_object_restriction
        raise GraphQL::ExecutionError.new("error: unauthorized access: #{:update} '#{model}', transaction cancelled")
      end
  
      item_associations = model.reflect_on_all_associations.select{|t| begin t.klass rescue next end}.select{|t| !t.options[:polymorphic]}
      item_association_names = item_associations.map{|m| m.name.to_s}
      input_association_names = item_association_names & inputs_root.to_h.keys
      
      item.transaction do
        #puts "***********item.update_attributes(#{inputs_root.to_h.except('id').except!(*item_association_names)})"
        #puts "***********ctx[current_user.to_sym].is_admin?(#{ctx[:current_user].is_admin?})"
        item.update_attributes(inputs_root.to_h.except('id').except('item_id').except!(*item_association_names))
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
              #puts "#{klass.name}  #{i.to_h}  #{model_name.downcase} #{inputs_root[:item_id]}"
              GraphqlModelMapper::Resolve.nested_update(ctx, klass.name, i, model_name.downcase, inputs_root[:item_id])
            end
          elsif !is_collection && belongs_to
            #puts "belongs_to"
            #puts "self.nested_update(#{ctx}, #{model.name}, #{lclinput.to_h}, nil, nil, #{ass.name}, #{inputs_root[:item_id]}, #{klass.name})"
            GraphqlModelMapper::Resolve.nested_update(ctx, model.name, lclinput, nil, nil, ass.name, inputs_root[:item_id], klass.name)
          elsif !is_collection && !belongs_to #has_one
            #puts "has_one"
            #puts "self.nested_update(#{ctx}, #{klass.name}, #{lclinput.to_h}, #{model_name.downcase}, #{inputs_root[:item_id]})"
            GraphqlModelMapper::Resolve.nested_update(ctx, model.name, lclinput, nil, nil, ass.name, inputs_root[:item_id], klass.name)
          end
        end
      end
      item
    end

    def self.get_filter_implied_includes(value, parent={})
      ##binding.pry
      result = {}
      value.keys.each do |key|
        if !value[key].is_a?(Array)
          target = self.get_filter_implied_includes(value[key], key)
          if target.empty?
            result[key] = {}
          else
            result[key] =  target 
          end
        end
      end
      result
    end
    
    @aliases=[]
    def self.apply_full_filter_with_aliases(scope, value, parent, parent_parent="")
      self.apply_full_filter(scope, value, parent, parent_parent="")
    end

    def self.apply_full_filter(scope, value, parent, parent_parent="")
      #binding.pry
      ##{reflection_name}_#{parent_table_name}
      value.keys.map(&:to_s).uniq.sort.each do |key|
        #if value[key] && value[key].keys.include?("compare")
        if value[key] && value[key].is_a?(Array)
          reflection_parent = scope.reflect_on_all_associations.select{|m| m.name == parent.to_sym}.length>0 ? scope.reflect_on_all_associations.select{|m| m.name == parent.to_sym}.first.klass.table_name : nil
          reflection_parent_parent = scope.reflect_on_all_associations.select{|m| m.name == parent_parent.to_sym}.length>0 ? scope.reflect_on_all_associations.select{|m| m.name == parent_parent.to_sym}.first.klass.table_name : nil
          reflection_parent = reflection_parent || parent || scope.table_name
          #binding.pry
          value[key].each do |val|
            if !parent_parent.empty? && @aliases.include?(reflection_parent) && @aliases.count(reflection_parent) > 1           
              scope = self.get_compare(scope, "#{parent.pluralize}_#{parent_parent.pluralize}.#{key}", val["compare"],  val["value"])
            else
              scope = self.get_compare(scope, "#{reflection_parent.pluralize}.#{key}", val["compare"],  val["value"])
            end
          end
          @aliases << reflection_parent
        else
          table_reference = scope.reflect_on_all_associations.select{|m| m.name == key.to_sym}.length > 0 ? scope.reflect_on_all_associations.select{|m| m.name == key.to_sym}.first.klass.table_name : scope.table_name
          #binding.pry
          @aliases << table_reference
          scope = self.apply_full_filter(scope, value[key], key, parent)
        end
      end if value.public_methods.include?(:keys)
      scope
    end
    

    def self.apply_short_filter(scope, value)
      # normalize filters from nested OR structure, to flat scope list
      branches = self.normalize_filters(scope, value).reduce { |a, b| b || a }
      scope = scope.merge branches
      scope = scope.limit(20)
    end

    def self.get_compare(scope, column, compare, value)
      out = "#{column}"
      out = out + (compare == "greaterThan" ? " > ?" : "")
      out = out + (compare == "lessThan" ? " < ?" : "")
      out = out + (compare == "equalTo" ? " = ?" : "")
      out = out + (compare == "notEqualTo" ? " != ?" : "")
      out = out + (compare == "lessThanOrEqualTo" ? " <= ?" : "")
      out = out + (compare == "greaterThanOrEqualTo" ? " >= ?" : "")
      out = out + (compare == "contains" ? " like ?" : "")
      out = out + (compare == "isNull" ? " is null" : "")
      out = out + (compare == "notNull" ? " is not null" : "")
      out = out + (compare == "isTrue" ? " = 1" : "")
      out = out + (compare == "isFalse" ? " = 0" : "")
      
      value = (compare == "contains" ? "%#{value}%" : value) 

      value = (["isNull", "notNull"].include?(compare) ? "" : value)

      ##binding.pry
  
      #include_table = column.split(".")[0].singularize.classify
      
      #if include_table != scope.name
        #scope.includes(include_table)
      #end
      puts [out, value]
      scope.where([out, value])
    end

    def self.normalize_filters(scope, value, branches = [])
      # add like SQL conditions
      value.each do |val|
        scope = get_compare(scope, val["column"], val["compare"], val["value"])
        branches << scope
        
        # continue to normalize down
        val['OR'].reduce(branches) { |s, v| self.normalize_filters(v, s) } if val['OR'].present?
      end


      branches
    end
    
    class ResolveWrapper
      def initialize(resolve_func)
        @resolve_func = resolve_func
      end
    
      def call(obj, args, ctx)
        @resolve_func.call(obj, args, ctx)
      end
    end
  end
end    