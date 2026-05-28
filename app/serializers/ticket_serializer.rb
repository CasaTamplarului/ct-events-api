# frozen_string_literal: true

class TicketSerializer < ApplicationSerializer
  attributes :id, :price

  attribute :name do |object|
    object.translations(params[:languages_code])&.name
  end

  attribute :description do |object|
    object.translations(params[:languages_code])&.description
  end
end
