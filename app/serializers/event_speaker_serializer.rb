# frozen_string_literal: true

class EventSpeakerSerializer < ApplicationSerializer
  attributes :name, :action_url

  attribute :image do |object|
    ApplicationSerializer.asset_url(object.image)
  end

  attribute :description do |object|
    object.translations(params[:languages_code])&.description
  end

  attribute :action_label do |object|
    object.translations(params[:languages_code])&.action_label
  end
end
