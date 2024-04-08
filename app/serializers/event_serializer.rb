# frozen_string_literal: true

class EventSerializer < ApplicationSerializer
  attributes :start_date, :end_date

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :fully_booked, &:fully_booked?
  attribute :starts_from, &:starts_from

  attribute :tickets do |object|
    return nil unless object.tickets

    TicketSerializer.new(object.tickets, params: { languages_code: params[:languages_code] })
  end
end
