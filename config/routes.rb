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
          resource :push_preferences,  only: :update, controller: 'me/push_preferences'
          resources :push_subscriptions, only: %i[create destroy], controller: 'me/push_subscriptions'
        end
        scope '/me/bookings' do
          get  :upcoming, to: 'me/bookings#upcoming'
          get  :past,     to: 'me/bookings#past'
          post :check,    to: 'me/bookings#check'
          delete ':order_reference',                to: 'me/bookings#cancel_order',    as: 'cancel_booking'
          patch  ':order_reference/attendees/:id',  to: 'me/bookings#update_attendee', as: 'update_booking_attendee'
          delete ':order_reference/attendees/:id',  to: 'me/bookings#cancel_attendee', as: 'cancel_booking_attendee'
          get ':order_reference/wallet/google',     to: 'me/bookings#wallet_google',   as: 'google_wallet_booking'
          get ':order_reference/attendees/:id/wallet/google', to: 'me/bookings#wallet_google_attendee',
                                                              as: 'google_wallet_attendee'
          get ':order_reference/wallet/apple', to: 'me/bookings#wallet_apple', as: 'apple_wallet_booking'
          get ':order_reference/attendees/:id/wallet/apple',  to: 'me/bookings#wallet_apple_attendee',
                                                              as: 'apple_wallet_attendee'
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

      namespace :admin do
        resources :push_notifications, only: :create
      end

      resources :uploads, only: :create

      namespace :scan do
        get  'events',      to: 'events#index'
        get  'search',      to: 'search#index'
        get  'meal_slots',  to: 'meal_slots#index'
        post 'meal_stamps', to: 'meal_stamps#create'
        scope '/orders/:order_reference' do
          get   '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end

      get '/unsubscribe', to: 'unsubscribe#show'

      scope '/orders/:order_reference/attendees/:id/wallet' do
        get 'google', to: 'wallet#google', as: 'public_google_wallet'
        get 'apple',  to: 'wallet#apple',  as: 'public_apple_wallet'
      end

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
