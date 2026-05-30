# frozen_string_literal: true

class TicketSerializer < ApplicationSerializer
  attributes :id, :food_included

  attribute :price do |object|
    params[:show_price] == false ? nil : object.price
  end

  attribute :name do |object|
    object.translations(params[:languages_code])&.name
  end

  attribute :description do |object|
    object.translations(params[:languages_code])&.description
  end
end
