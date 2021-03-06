# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  email                  :string(255)      default(""), not null
#  encrypted_password     :string(255)      default(""), not null
#  reset_password_token   :string(255)
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  confirmation_token     :string(255)
#  confirmed_at           :datetime
#  confirmation_sent_at   :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  first_name             :string(255)
#  last_name              :string(255)
#

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :confirmable,
         :validatable

  has_many :access_grants,
           class_name: 'Doorkeeper::AccessGrant',
           foreign_key: :resource_owner_id,
           dependent: :delete_all # or :destroy if you need callbacks

  has_many :access_tokens,
           class_name: 'Doorkeeper::AccessToken',
           foreign_key: :resource_owner_id,
           dependent: :delete_all # or :destroy if you need callbacks

  has_many :posts

  def json_attributes
    custom_attributes = attributes.clone
    custom_attributes.delete 'encrypted_password'
    custom_attributes.delete 'reset_password_token'
    custom_attributes.delete 'reset_password_sent_at'
    custom_attributes.delete 'remember_created_at'
    custom_attributes.delete 'confirmation_token'
    custom_attributes.delete 'confirmed_at'
    custom_attributes.delete 'confirmation_sent_at'
    custom_attributes
  end

  protected

  # overwrite devise confirmation_token generation
  # use confirmation_token as the inpupt code
  def generate_confirmation_token
    if self.confirmation_token && !confirmation_period_expired?
      @raw_confirmation_token = self.confirmation_token
    else
      ### START overwrite ###
      # self.confirmation_token = @raw_confirmation_token = Devise.friendly_token
      ### END overwrite ###

      # ensure unique confirmation_token
      loop do
        self.confirmation_token = @raw_confirmation_token = SecureRandom.alphanumeric(Rails.configuration.confirmation_token_length)
      break if !self.class.exists?(confirmation_token: self.confirmation_token)
      end

      self.confirmation_sent_at = Time.now.utc
    end
  end

  # overwrite devise confirmation_token generation
  # for users to receive simpler password reset code
  def set_reset_password_token
    ### START overwrite ###
    # raw, enc = Devise.token_generator.generate(self.class, :reset_password_token)
    raw, enc = Devise.token_generator.custom_generate(self.class, :reset_password_token)
    ### END overwrite ###

    self.reset_password_token   = enc
    self.reset_password_sent_at = Time.now.utc
    save(validate: false)
    raw
  end
end

class User::ParameterSanitizer < Devise::ParameterSanitizer
  def initialize(*)
    super
    permit(:account_update, keys: [:first_name, :last_name])
  end
end
