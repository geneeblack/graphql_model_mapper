# graphql_model_mapper
This project is a work in progress and is in a pre-alpha state. Many thanks to @AndyKriger [https://github.com/AndyKriger](url) who initiated and shared the original idea on the GraphQL issue thread [https://github.com/rmosolgo/graphql-ruby/issues/945](url). 

The graphql_model_mapper gem facilitates the generation of GraphQL objects based on the definition of your existing ActiveRecord models.

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

Note that the query and delete mutations do not have an input type defined since their arguments are currently generated internally:

    GraphqlModelMapper::GRAPHQL_DEFAULT_TYPES =
    query: {
        output_type: {
            required_attributes: [],    # attributes required in the type - empty list defaults to no required attributes
            excluded_attributes: [],    # exclude these attributes from the type - empty list defaults to no excluded attributes
            allowed_attributes: [],     # only allow these attributes in the type - empty list defaults to all attributes allowed
            foreign_keys: true,         # generate the foreign keys on the type
            primary_keys: true,         # generate the primary keys for the type
            validation_keys: false,     # generate non-nullable validation keys for the type
            association_macro: nil,     # generate the associations fo the type - nil defaults to all associations (other than those that are polymorphic), you may also specify :has_many or :belongs_to or :has_one
            source_nulls: false,        # use the null definitions that are defined by the database for the exposed attributes
            type_key: :query,           # internal identifier for the query/mutation type for which this type definition applies
            type_sub_key: :output_type  # internal sub-identifier for the input/output type for which this definition applies
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

or individually by using the 

    graphql_type
    
macro attribute on the model, passing the individual settings that differ from the defaults. i.e.


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

The method that you assign to the resolver should be a class method that accepts and orchestrates the parameters passed from GraphQL in the resolve. In this example it is simply calling a GraphQL::ExecutionError to output the contents of the input parameters. These methods could be anywhere in your application, they are not limited to the model on which they are defined.

Some other attributes that you can set on the graphql_query are 

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

The schema has the capability to use the cancancan gem to enable authorized access to the query and mutation fields based on the models, if implemented it also will control the availability of the associations assigne to the model based on their underlying model authorization. This is an optional setup and is not required.  

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

Once you have your models decorated with the graphql_query/graphql_update/graphql_create/graphql_delete attributes the next step is implementing your schema and adding it to your controller. For this example I am using a schema definition located at app/graphql/graphql_model_mapper_schema.rb. I have used [https://github.com/exAspArk/graphql-errors](url) to handle errors generated from the resolve methods. It is not required but it provides an easy way to setup error handling.

    #app/graphql/graphql_model_mapper_schema.rb
    require 'graphql_model_mapper'

    # these are options that can be passed to the schema initiation to enable query logging or for authorization setup
    # nesting_strategy can be :flat, **:shallow** or :deep
    # type_case can be **:camelize**, :underscore or :classify
    # the default values are shown below
    options = {:log_query_depth=>false, :log_query_complexity=>false, :use_backtrace=>false, :use_authorize=>false, :nesting_strategy=>:shallow, :type_case=>:camelize}
    GraphqlModelMapperSchema = **GraphqlModelMapper.Schema(use_authorize: true)**
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

so you may access and test your GraphQL queries. It is located at [https://github.com/rmosolgo/graphiql-rails](url). Once you have graphiql-rails you can setup the route 

    #config/routes.rb
    [YourApp]::Application.routes.draw do
      if Rails.env.development? || Rails.env.staging?   # you can restrict access to graphiql to specific environments here
        mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
      end

      post "/graphql", to: "graphql#execute"

      ....
    end

you can then reference your previously assigned schema in  app/controllers/graphql_contoller.rb

    #app/controllers/graphql_controller
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
            result = **GraphqlModelMapperSchema**.execute(query, variables: variables, context: context, operation_name: operation_name, except: ExceptFilter)

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/graphql_model_mapper.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
