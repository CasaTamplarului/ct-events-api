# frozen_string_literal: true

Rails.application.routes.draw do
  apipie

  get '_healthcheck', to: 'healthcheck#index'

  namespace :api do
    namespace :v1 do
      scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
        # Events
        namespace :events do
          resources :upcoming, only: :index
          resources :past, only: :index
          resources :hero, only: :index
        end

        resources :event, only: :show, param: :slug
      end
    end
  end
end
