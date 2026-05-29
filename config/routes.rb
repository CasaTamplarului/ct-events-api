# frozen_string_literal: true

Rails.application.routes.draw do
  apipie

  get '_healthcheck', to: 'healthcheck#index'

  namespace :api do
    namespace :v1 do
      namespace :auth do
        resource :facebook,  only: :create
        resource :google,    only: :create
        resource :microsoft, only: :create
        resource :me, only: %i[show update], controller: 'me' do
          patch :password, on: :member
        end
        resource :registration, only: :create
        resource :session, only: :create
        scope '/password' do
          post '/forgot', to: 'passwords#forgot'
          post '/reset',  to: 'passwords#reset'
        end
      end

      scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
        # Events
        namespace :events do
          resources :upcoming, only: :index
          resources :past, only: :index
          resources :hero, only: :index
        end

        resources :event, only: :show, param: :slug
        resources :orders, only: :create
      end
    end
  end
end
