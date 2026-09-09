import { Link } from "react-router-dom";
import "./LegalPage.css";

export default function TermsOfService() {
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
        <h1>Terms of Service</h1>
        <p className="legal-updated">Last updated September 9, 2026</p>

        <p>
          These terms cover your use of LineTracker. By using the app, you're agreeing to them.
          LineTracker is a small, independently-developed app — please read the sections below
          carefully, especially the ones about betting odds and data accuracy.
        </p>

        <h2>What LineTracker is</h2>
        <p>
          LineTracker lets you track a stock's price or a sports betting line and get notified
          when it crosses a target you set.
        </p>
        <div className="legal-callout">
          <p>
            <strong>LineTracker does not let you place bets or wagers, and it never handles
            money.</strong> It only displays odds that sportsbooks have already published
            publicly, for informational and alerting purposes. Any actual betting happens on the
            sportsbook's own platform, entirely outside this app.
          </p>
        </div>

        <h2>Not financial or betting advice</h2>
        <p>
          Nothing in LineTracker is investment, financial, or betting advice. Stock prices and
          betting odds are pulled from third-party sources and may be delayed, incomplete, or
          wrong. Don't make a financial decision based solely on what this app shows you — always
          verify with the original source (your brokerage, the sportsbook itself) before acting.
        </p>

        <h2>Age requirement</h2>
        <p>
          You must be at least 17 years old to use LineTracker, and you're responsible for
          following the gambling and betting laws in your own location — LineTracker doesn't
          verify legal betting age or jurisdiction on your behalf.
        </p>

        <h2>Your account</h2>
        <p>
          You sign in with your Google or Apple account. You're responsible for keeping that
          account secure — anyone with access to it can access your alerts. Don't share your
          account with anyone else.
        </p>

        <h2>Acceptable use</h2>
        <p>Please don't:</p>
        <ul>
          <li>Use the app in a way that overloads or abuses its servers or the data providers it relies on.</li>
          <li>Try to access another user's account or data.</li>
          <li>Use the app for anything illegal in your location.</li>
        </ul>
        <p>We may suspend or terminate an account that violates these terms.</p>

        <h2>Deleting your account</h2>
        <p>
          You can delete your account at any time from <strong>Settings → Delete Account</strong>{" "}
          inside the app. This immediately and permanently deletes your alerts and preferences.
        </p>

        <h2>No warranty</h2>
        <p>
          LineTracker is provided "as is," without warranty of any kind. We don't guarantee the
          app will always be available, error-free, or that the data it shows (prices, odds) is
          accurate or up to date. Third-party data providers can and do have outages or delays
          outside our control.
        </p>

        <h2>Limitation of liability</h2>
        <p>
          To the fullest extent permitted by law, LineTracker and its developer aren't liable for
          any loss — financial or otherwise — arising from your use of the app, including
          decisions made based on stock or odds data shown in it.
        </p>

        <h2>Changes to these terms</h2>
        <p>
          We may update these terms from time to time. If we do, we'll update the date at the top
          of this page. Continuing to use the app after a change means you accept the updated
          terms.
        </p>

        <h2>Contact us</h2>
        <p>
          Questions about these terms? Email{" "}
          <a href="mailto:saithanpanchaharan123@gmail.com">saithanpanchaharan123@gmail.com</a>.
        </p>
      </main>
    </div>
  );
}
