import os
import sib_api_v3_sdk
from sib_api_v3_sdk.rest import ApiException

BREVO_API_KEY = os.environ.get("BREVO_API_KEY")
SENDER_EMAIL = os.environ.get("SENDER_EMAIL", "your_verified_sender@example.com")
SENDER_NAME = "LineTracker"
LOGOKIT_TOKEN = os.environ.get("LOGOKIT_TOKEN", "")


def format_odds(price):
    if price is None: 
        return "N/A"
    
    if price > 0: 
        return f"+{price}"
    else: 
        return str(price)

def build_email_content(alert):
    triggered_at = alert.triggered_at.strftime("%B %d, %Y at %I:%M %p") if alert.triggered_at else "—"

    header = """
    <div style="background:#0B0E11;padding:24px 32px;">
    <span style="font-family:monospace;font-size:16px;font-weight:600;color:white;letter-spacing:0.04em;">LINE<span style="color:blue;">TRACKER</span></span>
    <p style="font-size:13px;color:#8B92A0;margin:8px 0 0;"></p>
    </div>
    """

    footer = f"""
    <div style="margin:24px 32px 28px;padding-top:20px;border-top:1px solid #eee;">
      <span style="font-size:11px;color:#aaa;">Triggered on {triggered_at}</span>
    </div>
    """

    if alert.alert_type == "Stock 🌱":
        LOGOKIT_TOKEN = os.environ.get("LOGOKIT_TOKEN", "")
        logo_url = f"https://img.logokit.com/ticker/{alert.ticker}?token={LOGOKIT_TOKEN}"
        subject = f"LineTracker: {alert.ticker} hit your target"
        body = f"""
        <div style="max-width:520px;margin:0 auto;background:white;border-radius:12px;overflow:hidden;font-family:sans-serif;">
          {header}
            <div style="padding:32px 32px 0;">
                <div style="display:flex;align-items:center;gap:20px;">
                    <img src="{logo_url}" width="60" height="60" style="border-radius:10px;flex-shrink:0;" />
                    <div>
                        <p style="font-size:22px;font-weight:700;color:#0B0E11;margin:0 0 4px;">{alert.ticker}</p>
                        <p style="font-size:14px;color:#8B92A0;margin:0;">{alert.company_name or "Stock price alert"}</p>
                    </div>
                </div>
            </div>

          <div style="margin:24px 32px;border-top:1px solid #eee;"></div>

          <div style="padding:0 32px;display:flex;align-items:center;gap:16px;">
            <div style="flex:1;background:#f8f8f8;border-radius:8px;padding:14px 16px;text-align:center;">
              <p style="font-size:11px;color:#8B92A0;text-transform:uppercase;letter-spacing:0.06em;margin:0 0 4px;">Previous</p>
              <p style="font-family:monospace;font-size:22px;font-weight:600;color:#0B0E11;margin:0;">${alert.current_value:.2f}</p>
            </div>

            <div style="display:flex;align-items:center;justify-content:center;padding:0 16px;align-self:stretch;">
                <span style="font-size:20px;color:#3DDC97;">→</span>
            </div>

            <div style="flex:1;background:#f0fdf8;border:1px solid #3DDC97;border-radius:8px;padding:14px 16px;text-align:center;">
              <p style="font-size:11px;color:#3DDC97;text-transform:uppercase;letter-spacing:0.06em;margin:0 0 4px;">Now</p>
              <p style="font-family:monospace;font-size:22px;font-weight:600;color:#3DDC97;margin:0;"> ${alert.target_value:.2f}</p>
            </div>
          </div>
          {footer}
        </div>
        """

    else:
        team_logo = alert.home_logo if alert.outcome_name == alert.home_team else alert.away_logo
        logo_html = f'<img src="{team_logo}" width="60" height="60" style="border-radius:50%;flex-shrink:0;" />' if team_logo else ""
        direction_symbol = "≥" if alert.direction == "above" else "≤"
        opponent = alert.home_team if alert.outcome_name == alert.away_team else alert.away_team
        team_logo = alert.home_logo if alert.outcome_name == alert.home_team else alert.away_logo
        logo_html = f'<img src="{team_logo}" width="60" height="60" style="border-radius:50%;flex-shrink:0;" />' if team_logo else ""
        direction_symbol = "≥" if alert.direction == "above" else "≤"
        opponent = alert.home_team if alert.outcome_name == alert.away_team else alert.away_team
        opponent_logo = alert.home_logo if alert.outcome_name == alert.away_team else alert.away_logo  # ← add
        bookmaker_domain = {
            "DraftKings": "draftkings.com",
            "FanDuel": "fanduelracing.com",
            "BetMGM": "betmgm.com",
            "BetRivers": "betrivers.com",
            "Bovada": "bovada.lv",
            "MyBookie.ag": "mybookie.ag",
            "BetOnline.ag": "betonline.ag",
            "LowVig.ag": "lowvig.ag",
            "BetUS": "betus.com.pa",
        }.get(alert.bookmaker, "")  

        LOGOKIT_TOKEN = os.environ.get("LOGOKIT_TOKEN", "")  

        bookmaker_logo_html = f'<img src="https://img.logokit.com/domain/{bookmaker_domain}?token={LOGOKIT_TOKEN}" width="16" height="16" style="border-radius:3px;vertical-align:middle;margin-right:4px;" />' if bookmaker_domain else ""  # ← add
        opponent_logo_html = f'<img src="{opponent_logo}" width="16" height="16" style="border-radius:50%;vertical-align:middle;margin-right:4px;" />' if opponent_logo else ""  # ← add
        current_display = f"+{int(alert.current_value)}" if alert.current_value and alert.current_value > 0 else str(int(alert.current_value)) if alert.current_value else "—"
        target_display = f"+{int(alert.target_value)}" if alert.target_value > 0 else str(int(alert.target_value))
        subject = f"{alert.outcome_name} odds hit your target"
        body = f"""

        <div style="max-width:520px;margin:0 auto;background:white;border-radius:12px;overflow:hidden;font-family:sans-serif;">
        {header}
        <div style="padding:32px 32px 0;">
            <div style="display:flex;align-items:center;gap:20px;">
            {logo_html}
            <div>
                <p style="font-size:22px;font-weight:700;color:#0B0E11;margin:0 0 4px;">{alert.outcome_name}</p>
                <p style="font-size:14px;color:#8B92A0;margin:0;">vs {opponent_logo_html}<span style="color:#0B0E11;font-weight:600;">{opponent}</span></p>            </div>
            </div>
        </div>
        <div style="margin:24px 32px;border-top:1px solid #eee;"></div>
        <div style="padding:0 32px;display:flex;align-items:center;gap:16px;">
            <div style="flex:1;background:#f8f8f8;border-radius:8px;padding:14px 16px;text-align:center;">
                <p style="font-size:11px;color:#8B92A0;text-transform:uppercase;letter-spacing:0.06em;margin:0 0 4px;">Previous</p>
                <p style="font-family:monospace;font-size:22px;font-weight:600;color:#0B0E11;margin:0;">{current_display}</p>
            </div>

            <div style="display:flex;align-items:center;justify-content:center;padding:0 16px;align-self:stretch;">
            <span style="font-size:20px;color:#3DDC97;">→</span>
            </div>

            <div style="flex:1;background:#f0fdf8;border:1px solid #3DDC97;border-radius:8px;padding:14px 16px;text-align:center;">
                <p style="font-size:11px;color:#3DDC97;text-transform:uppercase;letter-spacing:0.06em;margin:0 0 4px;">Now</p>
                <p style="font-family:monospace;font-size:22px;font-weight:600;color:#3DDC97;margin:0;">{target_display}</p>
            </div>
        </div>
        {footer}
        </div>
        """

    return subject, body

def send_alert_email(alert):
    """Sends an email through Brevo when an alert is triggered. Returns True on success."""

    if not BREVO_API_KEY:
        print("[email] BREVO_API_KEY not set — skipping email send")
        return False

    configuration = sib_api_v3_sdk.Configuration()
    configuration.api_key["api-key"] = BREVO_API_KEY

    api_instance = sib_api_v3_sdk.TransactionalEmailsApi(
        sib_api_v3_sdk.ApiClient(configuration)
    )

    subject, html_content = build_email_content(alert)

    send_smtp_email = sib_api_v3_sdk.SendSmtpEmail(
        sender={"name": SENDER_NAME, "email": SENDER_EMAIL},
        to=[{"email": alert.user_email}],
        subject=subject,
        html_content=html_content,
    )

    try:
        api_instance.send_transac_email(send_smtp_email)
        print(f"[email] Sent alert email for alert {alert.id} to {alert.user_email}")
        return True
    except ApiException as e:
        print(f"[email] Failed to send email for alert {alert.id}: {e}")
        return False