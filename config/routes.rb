# frozen_string_literal: true

Rails.application.routes.draw do
  apipie

  get '_healthcheck', to: 'healthcheck#index'
end
