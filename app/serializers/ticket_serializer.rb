# frozen_string_literal: true

class TicketSerializer < ApplicationSerializer
  attributes :id, :food_included, :for_leaders, :valid_from, :valid_to

  attribute :price do |object|
    params[:show_price] == false ? nil : object.price
  end

  attribute :name do |object|
    object.translations(params[:languages_code])&.name
  end

  attribute :description do |object|
    object.translations(params[:languages_code])&.description
  end

  attribute :meal_slots do |object|
    object.ticket_meal_slots
          .sort_by { |s| [s.occurs_on, s.sort || 0] }
          .map { |s| { meal_type: s.meal_type, occurs_on: s.occurs_on } }
  end

  attribute :allowed, if: proc { |object, _| object.for_leaders } do |object|
    user = params[:current_user]
    next false if user.nil?
    next true if user.role == 'admin'

    if object.ticket_allowed_users.any?
      object.ticket_allowed_users.any? { |tau| tau.user_id == user.id }
    else
      true
    end
  end
end
