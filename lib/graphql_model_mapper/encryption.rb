module GraphqlModelMapper
  module Encryption
    def self.key
      Digest::SHA256.digest(ENV['GRAPHQL_SECRET_TOKEN'] || ENV['SECRET_TOKEN'] || GraphqlModelMapper.secret_token)
    end

    def self.aes(m,t)
      (aes = OpenSSL::Cipher::Cipher.new('aes-256-cbc').send(m)).key = Digest::SHA256.digest(self.key)
      aes.update(t) << aes.final
    end
    
    def self.encode(text)
      Base64.encode64(ActiveSupport::Gzip.compress(aes(:encrypt, text))).strip
    end
    
    def self.decode(text)
      aes(:decrypt, ActiveSupport::Gzip.decompress(Base64.decode64(text)))
    end
  end
end