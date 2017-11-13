# GraphqlModelMapper

The graphql_model_mapper gem facilitates the generation of GraphQL objects based on the existing definition of your ActiveRecord models.

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

Initially, you will not have any models exposed as GraphQL types. To expose a model you can add the following macro attributes to your model definition:

graphql_query   ## to generate a GraphQL query object (and associatied GraphQL input/output types) for the model 
graphql_create  ## to generate a GraphQL create mutation object (and its associatied GraphQL input/output types) for the model
graphql_delete  ## to generate a GraphQL delete mutation object (and its associatied GraphQL input/output types) for the model
graphql_update  ## to generate a GraphQL update mutation object (and its associatied GraphQL input/output types) for the model

The default input/output types generated for the model are based on the following settings (which may be overriden by initializing GraphqlModelMapper::GRAPHQL_DEFAULT_TYPES in you own initializer. Note that the query and delete mutation do not have an input type defined since they currently generated internally:


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


## Other Options

The query and mutation objects have a default resolver defined that may be sufficient for your needs (with the exception of the create mutation which most likely will not be adequate for your implementation). In the event that you want to assign your own resolvers for your type you can override the default resolver for the type in the macro attribute in the following way:

graphql_query resolver: -> (obj, inputs, ctx){ raise GraphQL::ExecutionError.new(inputs.to_h.to_a) }

The method that you assign to the resolver should be a class method that accepts and orchestrates the parameters passed from GraphQL in the resolve. In this example it is simply calling a GraphQL::ExecutionError to output the contents of the input parameters. These methods could be anywhere in your application, they are not limited to the model on which they are defined.

Some other attributes that you can set on the graphql_query are 

## graphql_query

scope_methods:  # scope methods available to be used in the query, these should not be parameterized and must be written so that they do not collide with other tables which may be included in the associations
description:    # a short description of the query
arguments:      # a list of argument defintions to override the default arguments, if using your own arguments you will need to override the query resolver to act on those arguments, the default arguments exposed on the query are:

              [{:name=>:explain,   :type=>GraphQL::BOOLEAN_TYPE, :default=>nil},        # handled by the default resolver, outputs the top level sql for the operation
              {:name=>:id,    :type=>GraphQL::INT_TYPE, :default=>nil},                 # allows input of an id for top level record selection for the model
              {:name=>:ids,    :type=>GraphQL::INT_TYPE.to_list_type, :default=>nil},   # allows input of an array of ids for top level records selection for the model
              {:name=>:limit, :type=>GraphQL::INT_TYPE, :default=>50},                  # limits the number of records retuurned (defaults to 50 records)
              {:name=>:offset, :type=>GraphQL::INT_TYPE, :default=>nil},                # specifies an offset for the start of the records returned
              {:name=>:order,   :type=>GraphQL::STRING_TYPE, :default=>nil},            # a string value that is passed to ActiveRecord query specifying the output order 
              {:name=>:where, :type=>GraphQL::STRING_TYPE.to_list_type, :default=>nil}]  # a string array for use in ActiveRecord query, can be a string or a query/value array to be used by the query ["model.id =? and model.date is not nul]", "1"]
 
## graphql_delete

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/graphql_model_mapper.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
