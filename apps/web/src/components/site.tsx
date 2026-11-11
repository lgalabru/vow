'use client';

import { ArrowRight, ChevronDown, Github, KeyRound, Laptop, PenLine, Star } from 'lucide-react';
import { MotionConfig, motion, useScroll, useTransform } from 'motion/react';
import Image from 'next/image';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Bento } from './bento';
import { Device } from './device';

const steps = [
  {
    icon: Laptop,
    title: 'Set the team up on Mac.',
    body: 'Enroll members in person. Organize projects. Choose the people and threshold for each quorum.',
    device: 'The ceremony companion',
  },
  {
    icon: PenLine,
    title: 'Review on your iPad.',
    body: 'Import the request, inspect the details, and record your consent on a screen that does nothing else.',
    device: 'Your offline approval device',
  },
  {
    icon: KeyRound,
    title: 'Authorize. Then share.',
    body: 'Use your registered security key and iPad authentication. Export the approval for your team to collect.',
    device: 'A portable signed approval',
  },
];

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
      'No. This website is a product preview. It does not connect to a wallet, read a security key, collect signatures, or request access to your devices. The illustrations use sample data only.',
  },
];

/** True below the width where the landscape iPad's text stops being readable. */
function useNarrow() {
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    const query = window.matchMedia('(max-width: 760px)');
    const update = () => setNarrow(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);
  return narrow;
}

/** A block that rises into place the first time it scrolls into view. */
export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 28 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '0px 0px -12% 0px' }}
      transition={{ duration: 0.7, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}

function Hero() {
  const ref = useRef<HTMLElement>(null);
  const narrow = useNarrow();
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] });
  // The copy falls behind the scroll and fades; the iPad rises to meet it.
  const copyY = useTransform(scrollYProgress, [0, 1], [0, 180]);
  const copyOpacity = useTransform(scrollYProgress, [0, 0.55], [1, 0]);
  const deviceY = useTransform(scrollYProgress, [0, 1], [0, -150]);
  return (
    <section ref={ref} className="hero" aria-labelledby="hero-heading">
      <motion.div className="hero-copy shell" style={{ y: copyY, opacity: copyOpacity }}>
        <p className="tag">For iPad and Mac</p>
        <h1 id="hero-heading">
          Shared control.
          <br />
          <span>Personal approval.</span>
        </h1>
        <p className="lead">
          A dedicated iPad for your team&rsquo;s multisig approvals. Review the request, sign by
          hand, authorize with your security key. Offline the whole time.
        </p>
        <div className="actions">
          <a className="button" href="#workflow">
            See how it works <ArrowRight size={18} />
          </a>
          <a className="link" href="#questions">
            Read the questions
          </a>
        </div>
      </motion.div>
      <motion.div className="hero-device" style={{ y: deviceY }}>
        <Device portrait={narrow} />
        <p className="hero-note">Illustration with sample data. No signing keys are used.</p>
      </motion.div>
    </section>
  );
}

export const REPOSITORY = 'https://github.com/lgalabru/vow';

const defaultLinks = [
  { href: '#features', label: 'Features' },
  { href: '#workflow', label: 'How it works' },
  { href: '#questions', label: 'Questions' },
];

/**
 * The floating navigation. `stars` is the repository's star count, read on the
 * server; it is left out when GitHub could not be reached.
 */
export function Header({
  stars,
  links = defaultLinks,
}: {
  stars?: number | null;
  links?: { href: string; label: string }[];
}) {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <header className="site-header">
        <nav className="navigation" aria-label="Main navigation">
          <a className="brand" href="#" aria-label="Vow home">
            <Image src="/vow-icon.png" alt="" width={28} height={28} />
            vow
          </a>
          <div className="nav-links">
            {links.map((link) => (
              <a key={link.href} href={link.href}>
                {link.label}
              </a>
            ))}
          </div>
          <a className="nav-badge" href={REPOSITORY} target="_blank" rel="noreferrer">
            <Github size={16} />
            In development
            {stars != null && (
              <span className="nav-stars" aria-label={`${stars} GitHub stars`}>
                <Star size={12} fill="currentColor" />
                {new Intl.NumberFormat('en', { notation: 'compact' }).format(stars)}
              </span>
            )}
          </a>
        </nav>
      </header>
    </>
  );
}

export function Workflow() {
  return (
    <section className="section shell" id="workflow" aria-labelledby="workflow-heading">
      <Reveal className="heading">
        <h2 id="workflow-heading">
          Prepared together.
          <br />
          Approved individually.
        </h2>
        <p>Two apps share one process, and each member keeps their own approval.</p>
      </Reveal>
      <ol className="steps">
        {steps.map(({ icon: Glyph, title, body, device }, index) => (
          <li key={title}>
            <Reveal className="step" delay={index * 0.09}>
              <span className="step-icon">
                <Glyph size={24} strokeWidth={1.7} />
              </span>
              <span className="step-number">0{index + 1}</span>
              <h3>{title}</h3>
              <p>{body}</p>
              <span className="step-device">{device}</span>
            </Reveal>
          </li>
        ))}
      </ol>
    </section>
  );
}

export function Questions() {
  return (
    <section className="section shell narrow" id="questions" aria-labelledby="questions-heading">
      <Reveal className="heading">
        <h2 id="questions-heading">Good questions.</h2>
      </Reveal>
      <div className="faq">
        {questions.map((item) => (
          <details key={item.question}>
            <summary>
              {item.question}
              <span className="faq-toggle">
                <ChevronDown size={18} />
              </span>
            </summary>
            <p>{item.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

export function Closing() {
  return (
    <section className="shell" id="availability" aria-labelledby="availability-heading">
      <Reveal className="closing">
        <Image src="/vow-icon.png" alt="Vow app icon" width={72} height={72} />
        <p className="tag">Currently in development</p>
        <h2 id="availability-heading">
          Taking the time
          <br />
          to get it right.
        </h2>
        <p>
          Vow is an early prototype for iPad and Mac. Public availability will follow production
          validation.
        </p>
      </Reveal>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="site-footer shell">
      <a className="brand" href="#" aria-label="Vow home">
        vow
      </a>
      <p>Shared control. Personal approval.</p>
      <span>Made for iPad and Mac.</span>
    </footer>
  );
}

/** The public product page, with no account collection or third-party analytics. */
export function Site({ stars }: { stars?: number | null }) {
  return (
    <MotionConfig reducedMotion="user">
      <Header stars={stars} />
      <main id="main">
        <Hero />
        <section className="section shell" id="features" aria-labelledby="features-heading">
          <Reveal className="heading">
            <h2 id="features-heading">
              Built for one decision
              <br />
              at a time.
            </h2>
            <p>
              A browser is a busy place. Vow gives the request, your consent and your keys a screen
              of their own.
            </p>
          </Reveal>
          <Bento />
        </section>
        <Workflow />
        <Questions />
        <Closing />
      </main>
      <Footer />
    </MotionConfig>
  );
}
