#!/usr/bin/env ruby

require 'openssl'
require 'base64'

# Simple token. 
class Token
  attr_accessor :payload, :timestamp, :nonce, :separator
  
  def initialize
    @separator = "\t"
    @payload = nil
    @timestamp = Time.now.utc.to_i
    @nonce = Random.new.rand(10..9999)
  end
  
  def to_s
    [@payload, @timestamp, @nonce].join(@separator)
  end
  
  def to_a
    [@payload, @timestamp, @nonce]
  end
  
  def from_a(an_array)
    @payload, @timestamp, @nonce = an_array
  end
  
  def from_s(a_string)
    @payload, @timestamp, @nonce = a_string.split(@separator)
  end
  
end

# Makes a good webtoken. Can be used with a shared secret to send
# commands via URIs, create session tokens, etc.
class SecureToken < Token
  
  def initialize(key, iv)
    super()
    
    @key = key
    @iv = iv
    @aes = OpenSSL::Cipher.new("AES-256-CBC")
  end
  
  def to_e(base64_encode = false)
    @aes.encrypt
    @aes.key = @key
    @aes.iv = @iv
    token = @aes.update(self.to_s) + @aes.final
    return token unless base64_encode
    return Base64.urlsafe_encode64(token)
  end
  
  # Returns false if the token is too old, or test_secret doesn't match (if supplied) 
  # else true
  def verify(test_secret = false, time_tolerance_seconds = 60)
    return false if @timestamp.to_i+time_tolerance_seconds.to_i < Time.now.utc.to_i
    return !!(@payload == test_secret) if test_secret 
    return true
  end
  
  def from_token(token,base64_decode = false)
    
    token = Base64.urlsafe_decode64(token) if base64_decode
    
    @aes.decrypt
    @aes.key = @key
    @aes.iv = @iv
    self.from_s @aes.update(token) + @aes.final
  end
end