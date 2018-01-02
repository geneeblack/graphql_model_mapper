module GraphqlModelMapper
  class Railtie < Rails::Railtie
    initializer 'Rails logger' do
      GraphqlModelMapper.logger = Rails.logger
    end
  end
end

