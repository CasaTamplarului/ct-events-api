# frozen_string_literal: true

module Api
  module V1
    module Admin
      class WhatsappTemplatesController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_whatsapp) }

        def index
          templates = WhatsappTemplate.order(created_at: :desc)
          render json: templates.map { |t| template_json(t) }
        end

        def create
          variables = parse_variables(params[:variables])

          template = WhatsappTemplate.new(
            name: params[:name].presence,
            content_sid: params[:content_sid].presence,
            variables: variables
          )

          if template.save
            render json: template_json(template), status: :created
          else
            render json: { error: template.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        private

          def parse_variables(raw)
            Array(raw).map do |v|
              v.respond_to?(:to_unsafe_h) ? v.to_unsafe_h.slice('position', 'name') : v.slice('position', 'name')
            end
          end

          def template_json(tmpl)
            {
              id: tmpl.id,
              name: tmpl.name,
              content_sid: tmpl.content_sid,
              variables: tmpl.variables,
              created_at: tmpl.created_at
            }
          end
      end
    end
  end
end
