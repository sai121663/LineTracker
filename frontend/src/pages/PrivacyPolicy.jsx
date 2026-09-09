import { Link } from "react-router-dom";
import "./LegalPage.css";

export default function PrivacyPolicy() {
  return (
    <div className="legal-page">
      <header className="legal-header">
        <div className="legal-header-inner">
          <Link to="/" className="legal-logo">
            LINE<span className="legal-logo-accent">TRACKER</span>
          </Link>
          <Link to="/" className="legal-back">
            ← Back to app
          </Link>
        </div>
      </header>

      <main className="legal-main">
        <h1>Privacy Policy</h1>
        <p className="legal-updated">Last updated September 9, 2026</p>

        <p>
          This policy explains what information LineTracker collects, why, and how you can have
          it deleted. LineTracker is a small, independently-developed app for tracking stock
          prices and sports betting odds — it is not run by a company, and it does not sell your
          data to anyone.
        </p>

        <h2>Information we collect</h2>
        <p>When you sign in with Google or Apple, we receive:</p>
        <ul>
          <li>Your email address, which we use as your account identifier.</li>
        </ul>
        <p>We do not receive your password, contacts, photos, or anything else from your Google or Apple account.</p>
        <p>When you use the app, we store the information you create:</p>
        <ul>
          <li>The stock tickers or betting lines you choose to track, and the target price or odds you set.</li>
          <li>Your notification preferences (for example, whether email alerts are turned on).</li>
        </ul>
        <p>
          We do not collect your location, contacts, photos, microphone or camera data, and we do
          not use advertising or analytics tracking of any kind.
        </p>

        <h2>How we use this information</h2>
        <p>Your information is used only to run the app itself:</p>
        <ul>
          <li>To identify your account and show you the alerts you've created.</li>
          <li>To check stock prices and betting odds against your targets, and email you when one is hit.</li>
        </ul>
        <p>We never use your information for advertising, and we never sell it to third parties.</p>

        <h2>Third-party services we rely on</h2>
        <p>
          Running LineTracker means a few outside services see limited data in order to do their
          job — none of them receive more than they need to:
        </p>
        <ul>
          <li><strong>Google and Apple</strong> — verify your identity when you sign in; they don't see your alerts or activity in the app.</li>
          <li><strong>Yahoo Finance and SharpAPI</strong> — provide stock price and betting odds data. We send them the ticker or game you're tracking, not anything that identifies you.</li>
          <li><strong>Brevo (email delivery)</strong> — sends the email when one of your alerts is triggered.</li>
          <li><strong>Render and Supabase</strong> — host the app's server and database, where your account and alert data is stored.</li>
        </ul>

        <h2>Data retention and deletion</h2>
        <p>
          We keep your alerts and preferences for as long as your account exists. You can delete
          individual alerts at any time from the dashboard.
        </p>
        <p>
          You can permanently delete your account from inside the app: go to{" "}
          <strong>Settings → Delete Account</strong>. This immediately and permanently erases
          every alert and preference tied to your account. This cannot be undone.
        </p>
        <p>
          If you'd rather not use the in-app option, email us at{" "}
          <a href="mailto:saithanpanchaharan123@gmail.com">saithanpanchaharan123@gmail.com</a> and
          we'll delete your data manually.
        </p>

        <h2>Security</h2>
        <p>
          Your session is stored securely on your device (in the iOS Keychain, where supported),
          and all traffic between the app and our servers is encrypted (HTTPS).
        </p>

        <h2>Age requirement</h2>
        <div className="legal-callout">
          <p>
            LineTracker is not intended for anyone under 17. It displays sports betting odds
            (without letting you place any bets or wagers through the app), so we restrict it to
            the same age range the App Store uses for that kind of content.
          </p>
        </div>

        <h2>Changes to this policy</h2>
        <p>
          If this policy changes, we'll update the date at the top of this page. We won't make
          changes that reduce your rights over your own data without clearly notifying you first.
        </p>

        <h2>Contact us</h2>
        <p>
          Questions about this policy or your data? Email{" "}
          <a href="mailto:saithanpanchaharan123@gmail.com">saithanpanchaharan123@gmail.com</a>.
        </p>
      </main>
    </div>
  );
}
