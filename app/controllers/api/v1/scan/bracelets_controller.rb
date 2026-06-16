# frozen_string_literal: true

module Api
  module V1
    module Scan
      class BraceletsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action(only: %i[index generate]) { require_permission!(:can_manage_bracelets) }
        before_action(only: %i[assign show])    { require_permission!(:can_check_in_attendees) }

        ALPHABET     = (('A'..'Z').to_a + ('0'..'9').to_a).freeze
        MAX_QUANTITY = 500
        VALID_LENGTHS = [4, 5, 6].freeze

        def index
          event = Event.find_by(id: params[:event_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

          bracelets = Bracelet.where(event: event)
                              .includes(attendee: :order)
                              .order(:created_at)

          render json: {
            codes: bracelets.map do |b|
              {
                code: b.code,
                attendee_id: b.attendee_id,
                attendee_name: b.attendee ? "#{b.attendee.first_name} #{b.attendee.last_name}".strip : nil,
                order_reference: b.attendee&.order&.order_reference
              }
            end
          }
        end

        def generate
          event = Event.find_by(id: params[:event_id])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

          quantity    = params[:quantity].to_i
          code_length = params[:code_length].to_i

          unless quantity.between?(1, MAX_QUANTITY)
            return render json: { error: "quantity must be between 1 and #{MAX_QUANTITY}" },
                          status: :unprocessable_content
          end

          unless VALID_LENGTHS.include?(code_length)
            return render json: { error: "code_length must be one of #{VALID_LENGTHS.join(', ')}" },
                          status: :unprocessable_content
          end

          codes = generate_unique_codes(event.id, quantity, code_length)
          Bracelet.insert_all(codes.map do |c|
            { code: c, event_id: event.id, created_at: Time.current, updated_at: Time.current }
          end)

          render json: { codes: codes }, status: :created
        end

        def assign
          bracelet_code = params[:bracelet_code].to_s.strip
          attendee_id   = params[:attendee_id].to_i

          if bracelet_code.blank? || attendee_id.zero?
            return render json: { error: 'bracelet_code and attendee_id are required' },
                          status: :unprocessable_content
          end

          attendee = Attendee.includes(:order, :event).find_by(id: attendee_id)
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

          bracelet = nil
          ActiveRecord::Base.transaction do
            unassign_existing_bracelets(attendee)
            bracelet = Bracelet.find_or_initialize_by(code: bracelet_code)
            bracelet.event    = attendee.event
            bracelet.attendee = attendee
            bracelet.save!
          end

          if bracelet.persisted?
            render json: {
              code: bracelet.code,
              attendee_id: attendee.id,
              order_reference: attendee.order&.order_reference
            }
          else
            render json: { error: bracelet.errors.full_messages.first }, status: :unprocessable_content
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.first }, status: :unprocessable_content
        end

        def show
          bracelet = Bracelet.includes(attendee: :order).find_by(code: params[:code])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless bracelet
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless bracelet.attendee_id

          render json: {
            order_reference: bracelet.attendee.order&.order_reference,
            attendee_id: bracelet.attendee_id
          }
        end

        private

          def unassign_existing_bracelets(attendee)
            attendee_ids =
              if attendee.user_id.present?
                Attendee.where(event_id: attendee.event_id, user_id: attendee.user_id).pluck(:id)
              else
                [attendee.id]
              end

            Bracelet.where(event_id: attendee.event_id, attendee_id: attendee_ids)
                    .update_all(attendee_id: nil)
          end

          def generate_unique_codes(event_id, quantity, code_length)
            prefix     = event_id.to_s
            candidates = Set.new

            candidates << "#{prefix}-#{Array.new(code_length) do
              ALPHABET.sample
            end.join}" while candidates.size < quantity * 2

            existing     = Bracelet.where(code: candidates.to_a).pluck(:code).to_set
            unique_codes = candidates - existing

            # top up if there were collisions (extremely rare)
            until unique_codes.size >= quantity
              c = "#{prefix}-#{Array.new(code_length) { ALPHABET.sample }.join}"
              unique_codes << c unless existing.include?(c)
            end

            unique_codes.first(quantity)
          end
      end
    end
  end
end
