# graphql_model_mapper
This project is a work in progress and is in a pre-alpha state. Many thanks to @AndyKriger https://github.com/AndyKriger who initiated and shared the original idea on the GraphQL issue thread https://github.com/rmosolgo/graphql-ruby/issues/945. 

The graphql_model_mapper gem facilitates the generation of GraphQL objects based on the definition of your existing ActiveRecord models.

It has been tested on Rails 3.2, 4.1 and 5.0 using Ruby 2.1.10 and 2.2.8 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'graphql_model_mapper'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install graphql_model_mapper

## Usage

Initially, you will not have any models exposed as GraphQL types. To expose a model you can add any/all of the following macro attributes to your model definition:

    graphql_query   # to generate a GraphQL query object (and associated GraphQL input/output types) for the model 
    graphql_create  # to generate a GraphQL create mutation object (and its associated GraphQL input/output types) for the model
    graphql_delete  # to generate a GraphQL delete mutation object (and its associated GraphQL input/output types) for the model
    graphql_update  # to generate a GraphQL update mutation object (and its associated GraphQL input/output types) for the model

The default input/output types generated for the model are based on the default settings (which may be overriden by initializing GraphqlModelMapper::GRAPHQL_DEFAULT_TYPES in your own initializer 

    #config/initializers/grapqhql_model_mapper_init.rb
    GraphqlModelMapper::GRAPHQL_DEFAULT_TYPES = {
        query: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :output_type
            }
        },
        update: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :update,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :update,
                type_sub_key: :output_type
            }
        },
        delete: {
            input_type: {
                required_attributes: [:id], 
                excluded_attributes: [], 
                allowed_attributes: [:id], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :delete,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :delete,
                type_sub_key: :output_type
            }
        },
        create: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: false, 
                validation_keys: false, 
                association_macro: :has_many, 
                source_nulls: false,
                type_key: :create,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :create,
                type_sub_key: :output_type
            }
        }
    }

or individually by using the 

    graphql_type
    
macro attribute on the model, passing the individual settings that differ from the defaults. These will be merged into the default values. i.e.


    graphql_types query: {
    output_type: {
        excluded_attributes: [:crypted_password] 
      }
    }, 
    update: {
      input_type: {
        excluded_attributes: [:crypted_password] 
      },
      output_type: {
        excluded_attributes: [:crypted_password] 
      }  
    }, 
    create: { 
      input_type: {
        excluded_attributes: [:crypted_password] 
      },
      output_type: {
        excluded_attributes: [:crypted_password] 
      }
    }, 
    delete: { 
      input_type: {
        excluded_attributes: [:crypted_password] 
      },
      output_type: {
        excluded_attributes: [:crypted_password] 
      }
    }

or you can specify the **graphql_types** attribute on the model and initialize your own constant for the model in an initializer, these settings will not be merged into the default settings, so you will need to fully elucidate the types

    #config/initializers/grapqhql_model_mapper_init.rb
    GraphqlModelMapper::[YOUR_MODEL_NAME_CLASSIFIED_AND_CAPITALIZED]_GRAPHQL_DEFAULT_TYPES = {
        query: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :query,
                type_sub_key: :output_type
            }
        },
        update: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :update,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :update,
                type_sub_key: :output_type
            }
        },
        delete: {
            input_type: {
                required_attributes: [:id], 
                excluded_attributes: [], 
                allowed_attributes: [:id], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: false,
                type_key: :delete,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: false, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :delete,
                type_sub_key: :output_type
            }
        },
        create: {
            input_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: false, 
                validation_keys: false, 
                association_macro: :has_many, 
                source_nulls: false,
                type_key: :create,
                type_sub_key: :input_type
            },
            output_type: {
                required_attributes: [], 
                excluded_attributes: [], 
                allowed_attributes: [], 
                foreign_keys: true, 
                primary_keys: true, 
                validation_keys: false, 
                association_macro: nil, 
                source_nulls: true,
                type_key: :create,
                type_sub_key: :output_type
            }
        }
    }
## Other Options

The query and mutation objects have a default resolver defined that may be sufficient for your needs (with the exception of the create mutation which most likely will not be adequate for your implementation, currently it simply validates the input and does not attempt to add the record). 

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


If you want to assign your own resolvers for your type you can override the default resolver for the type on the macro attribute in the following way:

    graphql_query resolver: -> (obj, inputs, ctx){ raise GraphQL::ExecutionError.new(inputs.to_h.to_a) }

The method that you assign to the resolver should either be self contained or call a class method that accepts and orchestrates the parameters passed from GraphQL in the resolve. In this example it is simply calling a GraphQL::ExecutionError to output the contents of the input parameters. These methods could be anywhere in your application, they are not limited to the model on which they are defined.

When returning items to populate the appropriate output type, return them as a hash value shaped to fit the output types definition. GraphQL will take care of the final mapping and shapping of the models item(s)

    resolver: -> (obj, inputs, ctx){
        items = YourClass.method_that_returns_items(obj, inputs, ctx, name)
        {
            total: items.length,
            items: items
        }
    }
or

    resolver: -> (obj, inputs, ctx){
        item = YourClass.method_that_returns_an_item(obj, inputs, ctx, name)
        {
            item: item
        }
    }


Some other attributes that you can set on the graphql_query in addition to the resolver are 

## graphql_query

    description:    # a short description of the query
    scope_methods:  # scope methods available to be used in the query, these should not be parameterized and must be written so that they do not collide with other tables which may be included in the associations
    arguments:      # a list of argument definitions to override the default arguments, if using your own arguments you will need to override the query resolver to act on those arguments, the default arguments exposed on the query are:
    
    default_arguments =
    [{:name=>:explain,   :type=>GraphQL::BOOLEAN_TYPE, :default=>nil},        # handled by the default resolver, outputs the top level sql for the operation
    {:name=>:id,    :type=>GraphQL::INT_TYPE, :default=>nil},                 # allows input of an id for top level record selection for the model
    {:name=>:ids,    :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil},   # allows input of an array of ids for top level records selection for the model
    {:name=>:limit, :type=>GraphQL::INT_TYPE, :default=>50},                  # limits the number of records retuurned (defaults to 50 records)
    {:name=>:offset, :type=>GraphQL::INT_TYPE, :default=>nil},                # specifies an offset for the start of the records returned
    {:name=>:order,   :type=>GraphQL::STRING_TYPE, :default=>nil},            # a string value that is passed to ActiveRecord query specifying the output order 
    {:name=>:where, :type=>GraphQL::STRING_TYPE.to_list_type, :default=>nil}] # a string array for use in ActiveRecord query, can be a string or a query/value array to be used by the query ["model.id =? and model.date is not nul]", "1"]

## graphql_delete
    description:
    scope_methods:
    arguments:
    resolver:

## graphql_update
    
    description:
    resolver:

## graphql_create

    description:
    resolver:


## Optional Authorization

The schema has the capability to use the cancancan gem to enable authorized access to the query and mutation fields based on the models, if implemented it also will control the availability of the associations assigned to the model based on their underlying model authorization. This is an optional setup and is not required.  

    gem "cancancan", "~> 1.10"

Follow the setup for cancancan and create an app/model/ability.rb file to setup your access rights
        
    class Ability
        include CanCan::Ability

        def initialize(user)
            # Define abilities for the passed in user here. For example:
            #
            #   user ||= User.new # guest user (not logged in)
            #   if user.admin?
            #     can :manage, :all
            #   else
            #     can :read, :all
            #   end
            #
            # The first argument to `can` is the action you are giving the user
            # permission to do.
            # If you pass :manage it will apply to every action. Other common actions
            # here are :read, :create, :update and :destroy.
            #
            # The second argument is the resource the user can perform the action on.
            # If you pass :all it will apply to every resource. Otherwise pass a Ruby
            # class of the resource.
            #
            # The third argument is an optional hash of conditions to further filter the
            # objects.
            # For example, here the user can only update published articles.
            #
            #   can :update, Article, :published => true
            #
            # See the wiki for details:
            # https://github.com/CanCanCommunity/cancancan/wiki/Defining-Abilities
            

            user ||= User.new # guest user (not logged in)
            if user.is_admin?
                can :manage, :all
            else
                can :manage, [YourModelA] # this will allow access to :query, :create, :update, :delete GraphQL methods for defined models
                can :read,   [YourModelB] # this will allow access to :query GraphQL methods for defined models as well as allow read access to associations of that type
                can :create, [YourModelC] # this will allow access to :create GraphQL methods for defined models
                can :update, [YourModelD] # this will allow access to :update GraphQL methods for defined models
                can :delete, [YourModelE] # this will allow access to :delete GraphQL methods for defined models
                
            end

        end
    end


GraphqlModelMapper requires an optional ability method on your current_user in order to check the context current_users authorization to access a GraphQL objects model implementation.

    class User < ActiveRecord::Base
        def ability
            @ability ||= Ability.new(self)
        end

        ...
    end

## Schema implementation

Once you have your models decorated with the graphql_query/graphql_update/graphql_create/graphql_delete attributes the next step is implementing your schema and adding it to your controller. For this example I am using a schema definition located at app/graphql/graphql_model_mapper_schema.rb. I have used https://github.com/exAspArk/graphql-errors to handle errors generated from the resolve methods. It is not required but it provides an easy way to setup error handling.

    #app/graphql/graphql_model_mapper_schema.rb
    require 'graphql_model_mapper'

    # these are options that can be passed to the schema initiation to enable query logging or for authorization setup
    # nesting_strategy can be :flat, :shallow or :deep
    # type_case can be :camelize, :underscore or :classify
    # the default values are shown below
    options = {:log_query_depth=>false, :log_query_complexity=>false, :use_backtrace=>false, :use_authorize=>false, :nesting_strategy=>:shallow, :type_case=>:camelize}
    GraphqlModelMapperSchema = GraphqlModelMapper.Schema(use_authorize: true)
    GraphQL::Errors.configure(GraphqlModelMapperSchema) do

      rescue_from ActiveRecord::StatementInvalid do |exception|
        GraphQL::ExecutionError.new(exception.message)
      end

      rescue_from ActiveRecord::RecordNotFound do |exception|
        GraphQL::ExecutionError.new(exception.message)
      end


      rescue_from ActiveRecord::RecordInvalid do |exception|
        GraphQL::ExecutionError.new(exception.message)
      end

      rescue_from StandardError do |exception|
        GraphQL::ExecutionError.new(exception.message)
      end
    end

## Graphiql controller setup

I recommend that you install 

    gem "graphiql-rails"

so you may access and test your GraphQL queries. It is located at https://github.com/rmosolgo/graphiql-rails. Once you have graphiql-rails you can setup the route 

    #config/routes.rb
    [YourApp]::Application.routes.draw do
      if Rails.env.development? || Rails.env.staging?   # you can restrict access to graphiql to specific environments here
        mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
      end

      post "/graphql", to: "graphql#execute"

      ....
    end

you can then reference your previously assigned schema in  app/controllers/graphql_controller.rb

    #app/controllers/graphql_controller.rb
    class GraphqlController < ApplicationController
        def execute
            variables = ensure_hash(params[:variables])
            query = params[:query]
            operation_name = params[:operationName]
            context = {
                # Query context goes here, for example:
                current_user: current_user
            }
            
            begin
            if (logged_in?)# && current_user.is_admin?)
                Ability.new(current_user) if GraphqlModelMapper.use_authorize # set on GraphqlModelMapper.Schema initialization
            elsif Rails.env != "development"
                query = nil
            end
            result = GraphqlModelMapperSchema.execute(query, variables: variables, context: context, operation_name: operation_name, except: ExceptFilter)

            end
            render json: result
        end

        private
        # this class is exercised when use_authorize is true
        class ExceptFilter
            def self.call(schema_member, context)
                return false unless GraphqlModelMapper.use_authorize
                # true if field should be excluded, false if it should be included
                return false unless authorized_proc = schema_member.metadata[:authorized_proc]
                model_name = schema_member.metadata[:model_name]
                access_type = schema_member.metadata[:access_type]
                !authorized_proc.call(context, model_name, access_type)
            end
        end

        def ensure_hash(query_variables)
            if query_variables.blank?
            {}
            elsif query_variables.is_a?(String)
            JSON.parse(query_variables)
            else
            query_variables
            end
        end
    end
## Custom attribute types
The functionality included in the type generation uses the base type reported by ActiveRecord for the defintion of the Input/Output model field/argument types. In some case this is not sufficient. In the case that you are using ActiveRecord Enums (Rails >= 4.1) or you have stuffed formatted data into a field that you would like to display in a custom way there is an option for you to define a custom type for input/output of  that specialized data.

In order to support this functionality you will need to create an initializer for creation of your custom types. The naming convention will allow the GraphqlModelMapper to pickup your custom types for use in the generated schema in place of the default ActiveRecord db type.

Use the form "#{model_name.classified}#{db_column_name.classified}Attribute#{Input/Output}Type" to name your custom type in the following manner.

If your model name is "Job" and the attribute that you want to override the type is named "status", you will want to create a GraphQL object constant like the following:

    GraphqlModelMapper::CustomType::JobStatusAttributeInputType
    GraphqlModelMapper::CustomType::JobStatusAttributeOutputType

in the following example I will show you how to create an override type for a Rails >=4.1 Enum value

given the following definition in a model named 'Job' with an enum type mapped to the 'status' attribute

    class Job < ApplicationRecord
        enum status: { applied:0, enrolled: 100, accepted: 200, rejected: 300, cancelled: 400}
    end

to enable application of a custom type to handle the input/output of the AR enum value you would need to create custom types in an initilizer. In this case we will create config/initializers/graphql_model_mapper_init.rb to create those types.

If you do not need to intercept the values when the custom type is used in input/output you can simply assign a GraphQL enum to the custom type. (take note of the naming convention used in the last statement, since the custom type will be picked up by convention when the model types are built it is important that you follow the naming convention **exactly** to ensure your custom type is used, custom types should be defined and reside in the GraphqlModelMapper::CustomType namespace). Since we do not need to intercept the field/argument resolver/prepare for this type, both input and output can be directly assigned to the GraphQL enum type. **(this case is already handled by default in Rails >=4.1 so you will not need to establish a custom type for this built in support for Rails enums)**

**config/initializers/graphql_model_mapper_init.rb**

    #config/initializers/graphql_model_mapper_init.rb

    GraphqlModelMapper::CustomType::JobStatusAttributeEnumType = GraphQL::EnumType.define do
      name "JobStatusAttributeEnumType"
      value("Applied", "", value: 'applied')
      value("Enrolled", "", value: 'enrolled')
      value("Accepted", "", value: 'accepted')
      value("Rejectd", "", value: 'rejected')
      value("Cancelled", "", value: 'cancelled')
    end

    GraphqlModelMapper::CustomTypes::JobStatusAttributeOutputType = GraphqlModelMapper::CustomTypes::JobStatusAttributeInputType = GraphqlModelMapper::CustomTypes::JobStatusAttributeEnumType

In the event that you need to customize the way in which your custom types are used at runtime you will need to fully declare the field and argument that will be used with your custom type. In this example I am declaring the InputType and OutputType fully so that I can use additional functionality in the prepare/resolve methods.

**config/initializers/graphql_model_mapper_init.rb**

    #config/initializers/graphql_model_mapper_init.rb
    GraphqlModelMapper::CustomType::JobStatusAttributeEnumType = GraphQL::EnumType.define do
      name "JobStatusAttributeEnumType"
      value("Applied", "", value: 'applied')
      value("Enrolled", "", value: 'enrolled')
      value("Accepted", "", value: 'accepted')
      value("Rejectd", "", value: 'rejected')
      value("Cancelled", "", value: 'cancelled')
    end

    GraphqlModelMapper::CustomType::JobStatusAttributeOutputType = GraphQL::Field.define do
      name "JobStatusAttributeOutputType"
      type(GraphqlModelMapper::CustomType::JobStatusAttributeEnumType)
      description("testing")
      resolve ->(object, arguments, context) { 
        object.status 
      }
    end

    GraphqlModelMapper::CustomType::JobStatusAttributeInputType = GraphQL::Argument.define do
      name "JobStatusAttributeInputType"
      type (GraphqlModelMapper::CustomType::JobStatusAttributeEnumType)
      prepare ->(value, ctx) do
        value
      end
    end

once you have these types defined and have restarted your server you should be able to see the mapping to the custom type in your __schema__ view and be able to use the GraphQL enums for query and update.

**Note: when querying the model, you will still use the underlying value for the type if using it in a where clause since the query is sent directly to the db and has no knowlege of the Rails enum or GraphQL custom type.**

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/geneeblack/graphql_model_mapper.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
