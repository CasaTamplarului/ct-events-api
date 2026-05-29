# frozen_string_literal: true

class EventSerializer < ApplicationSerializer
  attributes :start_date, :end_date, :address, :location_name, :embed_url

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :description do |object|
    object.translations(params[:languages_code]).description
  end

  attribute :fully_booked, &:fully_booked?
  attribute :starts_from, &:starts_from

  attribute :tickets do |object|
    next nil if object.past? || object.tickets.empty?

    TicketSerializer.new(object.tickets, params: { languages_code: params[:languages_code] })
  end

  attribute :speakers do |object|
    next nil if object.event_speakers.empty?

    EventSpeakerSerializer.new(object.event_speakers, params: { languages_code: params[:languages_code] })
  end

  attribute :hero_image do |object|
    ApplicationSerializer.asset_url(object.hero_image)
  end

  attribute :hero_portrait do |object|
    ApplicationSerializer.asset_url(object.hero_portrait)
  end

  attribute :gallery do |object|
    object.event_gallery_items.map do |item|
      ApplicationSerializer.asset_url(item.directus_files_id)
    end
  end

  attribute :attendee_fields do |object|
    object.event_attendee_fields.map do |f|
      { field: f.field_name, required: f.required }
    end
  end
end
