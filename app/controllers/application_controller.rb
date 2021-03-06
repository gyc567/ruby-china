# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery
  helper_method :unread_notify_count
  helper_method :turbolinks_app?

  # Addition contents for etag
  etag { current_user.try(:id) }
  etag { unread_notify_count }
  etag { flash }
  etag { Setting.footer_html }
  etag { Rails.env.development? ? Time.now : Date.current }

  before_action do
    resource = controller_name.singularize.to_sym
    method = "#{resource}_params"
    params[resource] &&= send(method) if respond_to?(method, true)

    if devise_controller?
      devise_parameter_sanitizer.permit(:sign_in) { |u| u.permit(*User::ACCESSABLE_ATTRS) }
      devise_parameter_sanitizer.permit(:account_update) do |u|
        if current_user.email_locked?
          u.permit(*User::ACCESSABLE_ATTRS)
        else
          u.permit(:email, *User::ACCESSABLE_ATTRS)
        end
      end
      devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(*User::ACCESSABLE_ATTRS) }
    end

    User.current = current_user
    cookies.signed[:user_id] ||= current_user.try(:id)

    # hit unread_notify_count
    unread_notify_count
  end

  before_action :set_active_menu
  def set_active_menu
    @current = case controller_name
               when 'pages'
                 ['/wiki']
               else
                 ["/#{controller_name}"]
               end
  end

  before_action :set_locale
  def set_locale
    I18n.locale = user_locale

    # after store current locale
    cookies[:locale] = params[:locale] if params[:locale]
  rescue I18n::InvalidLocale
    I18n.locale = I18n.default_locale
  end

  def render_404
    render_optional_error_file(404)
  end

  def render_403
    render_optional_error_file(403)
  end

  def render_optional_error_file(status_code)
    status = status_code.to_s
    fname = %w(404 403 422 500).include?(status) ? status : 'unknown'
    render template: "/errors/#{fname}", format: [:html],
           handler: [:erb], status: status, layout: 'application'
  end

  rescue_from CanCan::AccessDenied do |_exception|
    redirect_to topics_path, alert: t('common.access_denied')
  end

  def store_location
    session[:return_to] = request.request_uri
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

  def redirect_referrer_or_default(default)
    redirect_to(request.referrer || default)
  end

  def unread_notify_count
    return 0 if current_user.blank?
    @unread_notify_count ||= Notification.unread_count(current_user)
  end

  def authenticate_user!(opts = {})
    if turbolinks_app?
      render text: '401 Unauthorized', status: 401 if current_user.blank?
    else
      super(opts)
    end
  end

  def turbolinks_app?
    agent_str = request.user_agent.to_s
    agent_str.include?('turbolinks-app')
  end

  private

  def user_locale
    params[:locale] || cookies[:locale] || http_head_locale || I18n.default_locale
  end

  def http_head_locale
    http_accept_language.language_region_compatible_from(I18n.available_locales)
  end
end
