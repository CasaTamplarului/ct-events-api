# frozen_string_literal: true

class TicketSerializer < ApplicationSerializer
  attributes :price

  attribute :name do |object|
    object.translations(params[:languages_code])&.name
  end
end
