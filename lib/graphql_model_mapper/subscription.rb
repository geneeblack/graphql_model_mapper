module GraphqlModelMapper
  module Subscription
    def self.graphql_subscription(name: name, description: description, resolver: resolver)
      input_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :input_type)
      output_type = GraphqlModelMapper::MapperType.get_ar_object_with_params(name, type_sub_key: :output_type)

      self.get_subscription(name, description, "Update", resolver, input_type, output_type, name.downcase, "item")
    end


    def self.get_subscription(name, description, operation_name, resolver, input_type, output_type, input_name, output_name)
    end
  end
end