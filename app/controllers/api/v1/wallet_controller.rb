# frozen_string_literal: true

module Api
  module V1
    class WalletController < ActionController::API
      def google
        attendee = find_attendee
        return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

        url = GoogleWalletService.new(attendee: attendee, language: lang).save_url
        redirect_to url, allow_other_host: true
      rescue GoogleWalletService::ApiError, StandardError => e
        Rails.logger.error("Public Google Wallet error for attendee #{attendee&.id}: #{e.class}: #{e.message}")
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end

      def apple
        attendee = find_attendee
        return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

        data = AppleWalletService.new(attendee: attendee, language: lang).pass_data
        send_data data,
                  type: 'application/vnd.apple.pkpass',
                  filename: "ticket-#{attendee.order.order_reference}.pkpass",
                  disposition: 'inline'
      rescue AppleWalletService::PassGenerationError, StandardError => e
        Rails.logger.error("Public Apple Wallet error for attendee #{attendee&.id}: #{e.class}: #{e.message}")
        render json: { error: 'Internal server error' }, status: :internal_server_error
      end

      private

        def find_attendee
          order = Order.find_by(order_reference: params[:order_reference])
          return unless order

          order.attendees
               .includes(:order, event: :events_translations)
               .find_by(id: params[:id])
        end

        def lang
          params[:lang].presence || 'ro-RO'
        end
    end
  end
end
