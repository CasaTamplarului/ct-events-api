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
        resource :apple,     only: :create
        resource :me, only: %i[show update destroy], controller: 'me' do
          patch :password, on: :member
          resource :email_preferences, only: :update, controller: 'me/email_preferences'
        end
        scope '/me/bookings' do
          get  :upcoming, to: 'me/bookings#upcoming'
          get  :past,     to: 'me/bookings#past'
          post :check,    to: 'me/bookings#check'
        end
        resource :registration, only: :create
        resource :session, only: :create
        scope '/password' do
          post '/forgot', to: 'passwords#forgot'
          post '/reset',  to: 'passwords#reset'
        end
        scope '/passkeys' do
          post 'register/options',     to: 'passkeys#register_options'
          post 'register',             to: 'passkeys#register'
          post 'authenticate/options', to: 'passkeys#authenticate_options'
          post 'authenticate',         to: 'passkeys#authenticate'
          get  '/',                    to: 'passkeys#index',   as: 'passkeys'
          delete ':id',                to: 'passkeys#destroy', as: 'passkey'
        end
      end

      namespace :scan do
        get 'search', to: 'search#index'
        scope '/orders/:order_reference' do
          get '/', to: 'orders#show', as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end

      get '/unsubscribe', to: 'unsubscribe#show'

      scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
        # Events
        namespace :events do
          resources :upcoming, only: :index
          resources :past, only: :index
          resources :hero, only: :index
          resources :listing, only: :index
        end

        resources :event, only: :show, param: :slug
        resources :orders, only: :create
      end
    end
  end
end
