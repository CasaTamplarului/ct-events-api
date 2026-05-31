# frozen_string_literal: true

module Api
  module V1
    module Auth
      class PasskeysController < ActionController::API
        include Authenticatable
        include LocaleSetter
        include UserSerialisable

        before_action :authenticate_user!, only: %i[register_options register index destroy]
        before_action :set_locale

        def register_options
          options = WebAuthn::Credential.options_for_create(
            user: {
              id: WebAuthn.configuration.encoder.encode(current_user.id.to_s),
              name: current_user.email.to_s,
              display_name: "#{current_user.first_name} #{current_user.last_name}"
            },
            exclude: current_user.passkeys.pluck(:external_id)
                     .map { |id| { id: id, type: 'public-key' } },
            authenticator_selection: { resident_key: 'required', user_verification: 'preferred' },
            attestation: 'none'
          )

          challenge_token = PasskeyChallengeService.encode(
            challenge: options.challenge,
            purpose: PasskeyChallengeService::PURPOSE_REGISTER,
            user_id: current_user.id
          )

          render json: options.as_json.merge('challenge_token' => challenge_token)
        end

        def register
          payload = decode_challenge!(PasskeyChallengeService::PURPOSE_REGISTER)
          return unless payload

          render_unauthorized_challenge and return unless payload['user_id'] == current_user.id

          webauthn_credential = WebAuthn::Credential.from_create(params)
          webauthn_credential.verify(payload['challenge'])
          return unless create_passkey!(webauthn_credential)

          render json: { verified: true }
        rescue WebAuthn::Error
          render json: { error: I18n.t('auth.errors.passkey_verification_failed') },
                 status: :unprocessable_content
        end

        def authenticate_options
          options = WebAuthn::Credential.options_for_get(
            allow: [],
            user_verification: 'preferred'
          )

          challenge_token = PasskeyChallengeService.encode(
            challenge: options.challenge,
            purpose: PasskeyChallengeService::PURPOSE_AUTHENTICATE
          )

          render json: options.as_json.merge('challenge_token' => challenge_token)
        end

        def authenticate
          payload = decode_challenge!(PasskeyChallengeService::PURPOSE_AUTHENTICATE)
          return unless payload

          passkey = Passkey.find_by!(external_id: params[:id])
          webauthn_credential = WebAuthn::Credential.from_get(params)
          webauthn_credential.verify(
            payload['challenge'],
            public_key: passkey.public_key,
            sign_count: passkey.sign_count.to_i
          )

          passkey.update!(sign_count: webauthn_credential.sign_count)

          user = passkey.user
          Attendee.backfill_user(email: user.email, user_id: user.id) if user.email.present?
          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }
        rescue ActiveRecord::RecordNotFound
          render json: { error: I18n.t('auth.errors.passkey_not_found') }, status: :not_found
        rescue WebAuthn::Error
          render json: { error: I18n.t('auth.errors.passkey_verification_failed') },
                 status: :unauthorized
        end

        def index
          passkeys = current_user.passkeys.order(:created_at).map do |pk|
            { id: pk.id, nickname: pk.nickname, created_at: pk.created_at }
          end
          render json: passkeys
        end

        def destroy
          passkey = current_user.passkeys.find(params[:id])
          passkey.destroy!
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { error: I18n.t('auth.errors.passkey_not_found') }, status: :not_found
        end

        private

          def render_unauthorized_challenge
            render json: { error: I18n.t('auth.errors.invalid_challenge_token') },
                   status: :unauthorized
          end

          def create_passkey!(webauthn_credential)
            current_user.passkeys.create!(
              external_id: webauthn_credential.id,
              public_key: webauthn_credential.public_key,
              sign_count: webauthn_credential.sign_count,
              nickname: params[:nickname]
            )
            true
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
            raise unless external_id_taken_error?(e)

            render json: { error: I18n.t('auth.errors.passkey_already_registered') },
                   status: :conflict
            false
          end

          def external_id_taken_error?(error)
            return true if error.is_a?(ActiveRecord::RecordNotUnique)
            return false unless error.is_a?(ActiveRecord::RecordInvalid)

            error.record.errors.where(:external_id, :taken).any?
          end

          def decode_challenge!(purpose)
            PasskeyChallengeService.decode(params[:challenge_token], expected_purpose: purpose)
          rescue PasskeyChallengeService::InvalidTokenError
            render json: { error: I18n.t('auth.errors.invalid_challenge_token') },
                   status: :unauthorized
            nil
          end
      end
    end
  end
end
