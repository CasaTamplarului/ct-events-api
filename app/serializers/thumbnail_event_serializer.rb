# frozen_string_literal: true

class ThumbnailEventSerializer < ApplicationSerializer
  attributes :start_date, :end_date

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :description do |object|
    object.translations(params[:languages_code]).description
  end

  attribute :description_sections do |object|
    sections = object.event_description_sections.includes(:event_description_section_translations)
    sections.map do |s|
      { label: s.label_for(params[:languages_code]),
        content: s.content_for(params[:languages_code]) }
    end
  end

  attribute :is_past, &:past?

  attribute :fully_booked do |object|
    object.past? ? nil : object.fully_booked?
  end

  attribute :starts_from do |object|
    object.past? ? nil : object.starts_from
  end

  attribute :tickets do |object|
    next nil if object.past?
    next nil unless object.tickets.any?

    TicketSerializer.new(object.tickets,
                         params: { languages_code: params[:languages_code], show_price: params[:show_price] })
  end

  attribute :slug, &:slug
  attributes :address, :location_name, :embed_url

  attribute :hero_image do |object|
    ApplicationSerializer.asset_url(object.hero_image)
  end

  attribute :hero_portrait do |object|
    ApplicationSerializer.asset_url(object.hero_portrait)
  end

  attribute :gallery_preview do |object|
    ApplicationSerializer.asset_url(object.event_gallery_items.first&.directus_files_id)
  end
end
