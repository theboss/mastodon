# frozen_string_literal: true

class Auth::RegistrationsController < Devise::RegistrationsController
  layout :determine_layout

  before_action :set_invite, only: [:new, :create]
  before_action :check_enabled_registrations, only: [:new, :create]
  before_action :configure_sign_up_params, only: [:create]
  before_action :set_sessions, only: [:edit, :update]
  before_action :set_instance_presenter, only: [:new, :create, :update]
  before_action :set_body_classes, only: [:new, :create, :edit, :update]
  prepend_before_action :check_recaptcha, only: [:create]

  def destroy
    not_found
  end

  protected

  def update_resource(resource, params)
    params[:password] = nil if Devise.pam_authentication && resource.encrypted_password.blank?
    super
  end

  def build_resource(hash = nil)
    super(hash)

    resource.locale      = I18n.locale
    resource.invite_code = params[:invite_code] if resource.invite_code.blank?

    resource.build_account if resource.account.nil?
  end

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up) do |u|
      u.permit({ account_attributes: [:username] }, :email, :password, :password_confirmation, :invite_code)
    end
  end

  def after_sign_up_path_for(_resource)
    new_user_session_path
  end

  def after_sign_in_path_for(_resource)
    set_invite

    if @invite&.autofollow?
      short_account_path(@invite.user.account)
    else
      super
    end
  end

  def after_inactive_sign_up_path_for(_resource)
    new_user_session_path
  end

  def after_update_path_for(_resource)
    edit_user_registration_path
  end

  def check_enabled_registrations
    redirect_to root_path if single_user_mode? || !allowed_registrations?
  end

  def allowed_registrations?
    Setting.open_registrations || @invite&.valid_for_use?
  end

  def invite_code
    if params[:user]
      params[:user][:invite_code]
    else
      params[:invite_code]
    end
  end

  private

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end

  def set_body_classes
    @body_classes = %w(edit update).include?(action_name) ? 'admin' : 'lighter'
  end

  def set_invite
    @invite = invite_code.present? ? Invite.find_by(code: invite_code) : nil
  end

  def determine_layout
    %w(edit update).include?(action_name) ? 'admin' : 'auth'
  end

  def set_sessions
    @sessions = current_user.session_activations
  end

  def check_recaptcha
    unless is_human?
      self.resource = resource_class.new sign_up_params
      set_instance_presenter
      resource.validate
      respond_with_navigational(resource) { render :new }
    end
  end

  concerning :RecaptchaFeature do
    if ENV['RECAPTCHA_ENABLED'] == 'true'
      def is_human?
        g_recaptcha_response = params["g-recaptcha-response"]
        return false unless g_recaptcha_response.present?
        verify_by_recaptcha g_recaptcha_response
      end
      def verify_by_recaptcha(g_recaptcha_response)
        conn = Faraday.new(url: 'https://www.google.com')
        res = conn.post '/recaptcha/api/siteverify', {
            secret: ENV['RECAPTCHA_SECRET_KEY'],
            response: g_recaptcha_response
        }
        j = JSON.parse(res.body)
        j['success']
      end
    else
      def is_human?; true end
    end
  end
end
