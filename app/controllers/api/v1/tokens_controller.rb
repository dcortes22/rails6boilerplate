# frozen_string_literal: true

module Api
  module V1
    class TokensController < Doorkeeper::TokensController
      include ApiRescues

      before_action :doorkeeper_authorize!, only: [:revoke]

      resource_description do
        name 'Authentication-tokens'
        resource_id 'Authentication-tokens'
        api_versions 'v1' # , 'v2'
      end

      api :POST, '/login', 'Return JWT access_token and refresh_token'
      description 'Returns JWT access_token and refresh_token'
      param :email, URI::MailTo::EMAIL_REGEXP, required: true
      param :password, String, desc: "Length #{Devise.password_length.to_a.first} to #{Devise.password_length.to_a.last}", required: true
      param :grant_type, %w[password], required: true
      def login
        user = User.find_for_database_authentication(email: params[:email])

        case
        when user.nil? || !user.valid_password?(params[:password])
          response_code = 'devise.failure.invalid'
          render json: {
            response_code: response_code,
            response_message: I18n.t(response_code)
          }, status: 400
        when user&.inactive_message == :unconfirmed
          response_code = 'devise.failure.unconfirmed'
          render json: {
            response_code: response_code,
            response_message: I18n.t(response_code)
          }, status: 400
        when !user.active_for_authentication?
          create
        else
          create
        end
      end

      api :POST, '/refresh', 'Gets JWT refresh_token'
      description 'Gets JWT refresh_token'
      param :refresh_token, String, desc: 'refresh_token to get new access_token'
      param :grant_type, %w[refresh_token], required: true
      def refresh
        # essentially same method as create
        # but differentiating it for better api documentation
        create
      end

      api :POST, '/logout', 'Revokes tokens.'
      description 'Revokes tokens.'
      header 'Authorization', 'Bearer [your_access_token]', required: true
      header 'Content-Type', 'application/json', required: true
      header 'Accept', 'application/json', required: true
      def revoke
        # Follow doorkeeper-5.1.0 method, different from the latest code on the repo on 6 Sept 2019

        params[:token] = access_token

        revoke_token if authorized?
        response_code = 'custom.success.default'
        render json: {
          response_code: response_code,
          response_message: I18n.t(response_code)
        }, status: 200
      end

      private

      def access_token
        pattern = /^Bearer /
        header = request.headers['Authorization']
        header.gsub(pattern, '') if header && header.match(pattern)
      end
    end
  end
end

#### OVERWRITE ####
# need add `response_code` and `response_message` to response for standardization

module Doorkeeper
  module OAuth
    class ErrorResponse
      # overwrite, do not use default error and error_description key
      def body
        {
          response_code: "doorkeeper.errors.messages.#{name}",
          response_message: description,
          state: state
        }
      end
    end
  end
end

module Doorkeeper
  module OAuth
    class TokenResponse
      def body
        {
          # copied
          "access_token" => token.plaintext_token,
          "token_type" => token.token_type,
          "expires_in" => token.expires_in_seconds,
          "refresh_token" => token.plaintext_refresh_token,
          "scope" => token.scopes_string,
          "created_at" => token.created_at.to_i,
          # custom
          response_code: 'custom.success.default',
          response_message: I18n.t('custom.success.default')
        }.reject { |_, value| value.blank? }
      end
    end
  end
end
