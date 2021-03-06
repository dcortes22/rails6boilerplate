# frozen_string_literal: true

module Api
  module V1
    class PostsController < Api::BaseController
      resource_description do
        name 'Posts'
        resource_id 'Posts'
        api_versions 'v1' # , 'v2'
      end

      api :GET, '/posts', "Returns all of user's posts"
      description "Returns all of user's posts"
      header 'Authorization', 'Bearer [your_access_token]', required: true
      def index
        @posts = current_user.posts
      end
    end
  end
end
