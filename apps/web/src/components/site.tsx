'use client';

import { Button } from '@solana/design-system/button';
import Image from 'next/image';
import {
  ArrowDown,
  ArrowRight,
  Check,
  ChevronDown,
  Fingerprint,
  KeyRound,
  Laptop,
  PenLine,
  WifiOff,
} from 'lucide-react';
import { AppPreview } from './app-preview';

const questions = [
  {
    question: 'What is Vow?',
    answer:
      'Vow is a prototype for teams that share control of a Solana multisig. The Mac companion coordinates enrollment and prepares requests. A separate iPad reviews requests, collects consent, and exports locally verified approvals.',
  },
  {
    question: 'Why a dedicated iPad?',
    answer:
      'A separate device gives each member a focused place to inspect and approve a request. The iPad app locks approval when a network connection is present. Requests and approvals move as files, so the device can stay offline during signing.',
  },
  {
    question: 'What does the security key do?',
    answer:
      'A registered USB-C security key provides a second cryptographic proof for an approval. Vow verifies its signature alongside the device signature. The native Apple flow uses the key’s existing FIDO2 PIN and touch prompt. It does not reset your PIN.',
  },
  {
    question: 'Is the handwritten signature a biometric check?',
    answer:
      'No. Handwriting records explicit consent to the request. Vow does not currently match handwriting or claim that Apple Pencil proves who signed. The cryptographic approval uses the registered security key and the iPad’s protected signing key.',
  },
  {
    question: 'Can I use Vow with a live treasury?',
    answer:
      'Not yet. The native apps are prototypes. Production ceremony verification, recovery, attestations, and the on-chain multisig adapter remain in development. There is no public App Store or TestFlight release, and prototype approvals cannot execute a real transfer.',
  },
  {
    question: 'Does the website connect to my wallet?',
    answer:
      'No. This website is a product preview. It does not connect to a wallet, read a security key, collect signatures, or request access to your devices. The interactive example uses sample data only.',
  },
];

/** The public product page, with no account collection or third-party analytics. */
export function Site() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <header className="site-header">
        <nav className="shell navigation" aria-label="Main navigation">
          <a className="brand" href="#" aria-label="Vow home">
            <Image src="/vow-icon.png" alt="" width={34} height={34} />
            vow
          </a>
          <div className="nav-links">
            <a href="#workflow">How it works</a>
            <a href="#principles">Principles</a>
            <a href="#questions">Questions</a>
          </div>
          <a className="preview-badge" href="#availability">
            In development <ArrowUpRightIcon />
          </a>
        </nav>
      </header>
      <main id="main">
        <section className="hero shell" aria-labelledby="hero-heading">
          <p className="eyebrow">VOW FOR IPAD & MAC</p>
          <h1 id="hero-heading">
            Shared control.
            <br />
            <span>Personal approval.</span>
          </h1>
          <p className="vow-lead">
            A dedicated place for your team’s approvals.
            <br className="desktop-break" /> Built for iPad. Designed to stay offline.
          </p>
          <div className="vow-actions">
            <Button asChild radius="round" className="pill-button">
              <a href="#experience">
                Explore the app <ArrowDown size={17} />
              </a>
            </Button>
            <a className="text-link" href="#workflow">
              How it works <ArrowRight size={17} />
            </a>
          </div>
          <AppPreview />
        </section>

        <section className="introduction shell" aria-labelledby="intro-heading">
          <p className="eyebrow">A MOMENT TO BE CERTAIN</p>
          <h2 id="intro-heading">
            Give important decisions
            <br />
            their own space.
          </h2>
          <p>
            A browser is a busy place. An approval deserves your full attention. Vow brings the
            request, your consent, and your signing devices into one considered flow.
          </p>
        </section>

        <section className="workflow-section" id="workflow" aria-labelledby="workflow-heading">
          <div className="shell">
            <div className="section-heading">
              <p className="eyebrow">TWO APPS. ONE SHARED PROCESS.</p>
              <h2 id="workflow-heading">
                Prepared together.
                <br />
                Approved individually.
              </h2>
            </div>
            <div className="workflow-grid">
              <article className="workflow-step">
                <span className="step-number">01</span>
                <div className="workflow-icon">
                  <Laptop />
                </div>
                <h3>Set the team up on Mac.</h3>
                <p>
                  Enroll members in person. Organize projects. Choose the people and threshold for
                  each quorum.
                </p>
                <span className="step-device">THE CEREMONY COMPANION</span>
              </article>
              <article className="workflow-step">
                <span className="step-number">02</span>
                <div className="workflow-icon">
                  <PenLine />
                </div>
                <h3>Review on your iPad.</h3>
                <p>
                  Import the request, inspect the details, and record your consent. A focused screen
                  for a deliberate decision.
                </p>
                <span className="step-device">YOUR OFFLINE APPROVAL DEVICE</span>
              </article>
              <article className="workflow-step">
                <span className="step-number">03</span>
                <div className="workflow-icon">
                  <KeyRound />
                </div>
                <h3>Authorize. Then share.</h3>
                <p>
                  Use your registered security key and iPad authentication. Export the approval for
                  your team to collect.
                </p>
                <span className="step-device">A PORTABLE SIGNED APPROVAL</span>
              </article>
            </div>
          </div>
        </section>

        <section
          className="principles-section shell"
          id="principles"
          aria-labelledby="principles-heading"
        >
          <div className="section-heading">
            <p className="eyebrow">PURPOSEFUL BY DESIGN</p>
            <h2 id="principles-heading">
              Less distraction.
              <br />
              More intention.
            </h2>
          </div>
          <div className="principle-grid">
            <article className="principle offline-principle">
              <div className="offline-emblem">
                <WifiOff />
              </div>
              <div>
                <span className="small-label">A VISIBLE BOUNDARY</span>
                <h3>Offline means offline.</h3>
                <p>
                  The iPad app pauses approval when it detects a network connection. Its connection
                  status stays visible, so you know when the device is ready.
                </p>
              </div>
              <div className="offline-example">
                <WifiOff />
                <span>Offline</span>
                <Check />
              </div>
            </article>
            <article className="principle device-principle">
              <Fingerprint className="principle-glyph" />
              <div>
                <span className="small-label">PERSONAL TO YOUR DEVICE</span>
                <h3>
                  Your approval.
                  <br />
                  Your keys.
                </h3>
                <p>
                  A device-bound Secure Enclave key, biometric authentication, and a registered
                  security key bring separate checks to each approval.
                </p>
              </div>
            </article>
          </div>
        </section>

        <section
          className="questions-section shell"
          id="questions"
          aria-labelledby="questions-heading"
        >
          <div className="section-heading">
            <p className="eyebrow">A FEW DETAILS</p>
            <h2 id="questions-heading">Good questions.</h2>
          </div>
          <div className="faq-list">
            {questions.map((item) => (
              <details key={item.question}>
                <summary>
                  {item.question}
                  <ChevronDown size={19} />
                </summary>
                <p>{item.answer}</p>
              </details>
            ))}
          </div>
        </section>

        <section
          className="availability-section shell"
          id="availability"
          aria-labelledby="availability-heading"
        >
          <Image src="/vow-icon.png" alt="Vow app icon" width={72} height={72} />
          <p className="eyebrow">CURRENTLY IN DEVELOPMENT</p>
          <h2 id="availability-heading">
            Taking the time
            <br />
            to get it right.
          </h2>
          <p>
            Vow is an early prototype for iPad and Mac.
            <br />
            Public availability will follow production validation.
          </p>
          <a className="text-link" href="#experience">
            Take another look <ArrowRight size={17} />
          </a>
        </section>
      </main>
      <footer className="site-footer shell">
        <a className="brand" href="#" aria-label="Vow home">
          vow
        </a>
        <p>Shared control. Personal approval.</p>
        <span>Made for iPad & Mac.</span>
      </footer>
    </>
  );
}

function ArrowUpRightIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path
        d="M4 12 12 4M4 4h8v8"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
