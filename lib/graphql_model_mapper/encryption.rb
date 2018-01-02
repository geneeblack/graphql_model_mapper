module GraphqlModelMapper
  module Encryption
    def self.key
      secret = ENV['GRAPHQL_SECRET_TOKEN'] || ENV['SECRET_TOKEN'] || GraphqlModelMapper.secret_token || nil
      return nil if secret.nil?
      Digest::SHA256.digest(secret)
    end

    def self.aes(m,t)
      (aes = OpenSSL::Cipher::Cipher.new('aes-256-cbc').send(m)).key = Digest::SHA256.digest(self.key)
      aes.update(t) << aes.final
    end
    
    def self.encode(text)
      return text if self.key.nil?
      Base64.encode64(ActiveSupport::Gzip.compress(aes(:encrypt, text))).strip
    end
    
    def self.decode(text)
      return text if self.key.nil?
      aes(:decrypt, ActiveSupport::Gzip.decompress(Base64.decode64(text)))
    end
  end
end