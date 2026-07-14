# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  apipie

  get '_healthcheck', to: 'healthcheck#index'

  namespace :api do
    namespace :v1 do
      namespace :auth do
        resource :facebook, only: :create
        get 'facebook/callback', to: 'facebooks#callback'
        resource :google,    only: :create
        resource :microsoft, only: :create
        resource :apple,     only: :create
        # Sign in with Apple web flow for the mobile apps: Apple form_posts
        # here, and the token is bounced into the app via its deep link.
        post 'apple/callback', to: 'apples#callback'
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
        resources :emails, only: %i[index create show] do
          collection { get :variables }
        end
        resources :whatsapp_templates,  only: %i[index create]
        resources :whatsapp_broadcasts, only: %i[index create]
        scope '/events/:event_slug' do
          get  'qa_sessions', to: 'qa_sessions#index', as: 'admin_event_qa_sessions'
          post 'qa_sessions', to: 'qa_sessions#create'
        end
        scope '/qa_sessions/:code' do
          patch  '/',             to: 'qa_sessions#update', as: 'admin_qa_session'
          delete '/',             to: 'qa_sessions#destroy'
          get    'questions',     to: 'qa_questions#index',   as: 'admin_qa_session_questions'
          delete 'questions/:id', to: 'qa_questions#destroy', as: 'admin_qa_session_question'
        end
        scope '/events/:event_slug' do
          resources :event_teams, path: 'teams', only: %i[index create update destroy] do
            resources :score_entries, only: %i[index create],
                                      controller: 'event_team_score_entries'
          end
        end
      end

      resources :uploads, only: :create

      namespace :scan do
        get  'events',      to: 'events#index'
        get  'search',      to: 'search#index'
        get  'meal_slots',  to: 'meal_slots#index'
        post 'meal_stamps', to: 'meal_stamps#create'
        scope '/wheel' do
          get    '/',                    to: 'wheel#index'
          post   'spin',                 to: 'wheel#spin',          as: 'scan_wheel_spin'
          post   ':attendee_id/winner',  to: 'wheel#mark_winner',   as: 'scan_wheel_mark_winner'
          delete ':attendee_id/winner',  to: 'wheel#unmark_winner', as: 'scan_wheel_unmark_winner'
        end
        scope '/orders/:order_reference' do
          get   '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
        scope '/bracelets' do
          get  '/',        to: 'bracelets#index',    as: 'scan_bracelets'
          post 'generate', to: 'bracelets#generate', as: 'scan_bracelets_generate'
          post 'assign',   to: 'bracelets#assign',   as: 'scan_bracelets_assign'
          get  ':code',    to: 'bracelets#show',     as: 'scan_bracelet'
        end
      end

      # Mobile device push registration — auth optional (anonymous devices
      # only receive marketing broadcasts).
      get    'push_subscriptions', to: 'push_subscriptions#show'
      post   'push_subscriptions', to: 'push_subscriptions#create'
      delete 'push_subscriptions', to: 'push_subscriptions#destroy'

      get '/unsubscribe', to: 'unsubscribe#show'
      get '/orders/booking/:token', to: 'booking_token#show', as: 'booking_by_token'

      scope '/orders/:order_reference/attendees/:id/wallet' do
        get 'google', to: 'wallet#google', as: 'public_google_wallet'
        get 'apple',  to: 'wallet#apple',  as: 'public_apple_wallet'
      end

      get 'qa/:code', to: 'qa_sessions#resolve', as: 'public_qa_resolve'

      scope '/events/:event_slug/qa/:code' do
        get    '/',                           to: 'qa_sessions#show',    as: 'public_qa_session'
        post   'questions',                   to: 'qa_questions#create', as: 'public_qa_questions'
        delete 'questions/:id',               to: 'qa_questions#destroy', as: 'public_qa_question'
        post   'questions/:question_id/vote', to: 'qa_votes#create', as: 'public_qa_vote'
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
