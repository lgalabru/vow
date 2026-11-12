'use client';

import { ChevronDown, Github, Star } from 'lucide-react';
import { motion } from 'motion/react';
import Image from 'next/image';
import { type ReactNode } from 'react';

const questions = [
  {
    question: 'What is Vow?',
    answer:
      'Vow turns an iPad mini into an offline signing station for a team that shares control of a Solana multisig. A Mac companion runs the setup ceremony and prepares requests. Each member reviews a request on their own iPad, confirms it with three factors, and exports an approval.',
  },
  {
    question: 'Why an app on an iPad instead of a browser wallet?',
    answer:
      'Most attacks on signers arrive through the browser: a compromised site, a malicious extension, a swapped address. On the iPad, Vow is a sandboxed, signed app on a device that does nothing else, so that route is closed by design. It is not immune to everything. Every imported file is still treated as hostile, and unknown instructions block signing.',
  },
  {
    question: 'How is offline enforced?',
    answer:
      'By the app first: it locks approval while any network path is available and unlocks by itself when there is none. A team can add device management on top, since iPads are built for it, and make the restriction a policy. That is optional, and it makes whoever administers the devices a party you trust.',
  },
  {
    question: 'How does a transaction reach an offline iPad?',
    answer:
      'As a file. The iPad accepts raw transaction bytes, or a .vow file that also carries review context and the accounts the transaction touches. Today files move by AirDrop, USB storage or the Files app, and the approval leaves the same way. AirDrop needs the radios on, so it is not an air gap. QR codes are planned for teams that want no connection of any kind.',
  },
  {
    question: 'How do I know what I am signing?',
    answer:
      'The app decodes each instruction and its accounts, and refuses to sign what it cannot decode. With a .vow file it replays the transaction on the iPad, offline, against the accounts in the file. Apple’s on-device model can then explain the decoded facts in plain language, with no cloud fallback; if the model is unavailable, the facts are still there. Today the replay runs on synthetic state, not authenticated chain state.',
  },
  {
    question: 'What does an approval prove?',
    answer:
      'That it was made on this iPad, with this security key, by this member. The app records that evidence with each approval. The design is to attach it to the signature so a program can check it on-chain; that enforcement, and the Squads adapter it needs, are not finished.',
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
      'Not yet. Vow is experimental and unaudited. The apps produce prototype approval evidence, not executable Squads votes. Production enforcement, authenticated chain state, recovery and an independent security review remain unfinished. There is no public App Store or TestFlight release.',
  },
  {
    question: 'Does the website connect to my wallet?',
    answer:
      'No. This website is a product preview. It does not connect to a wallet, read a security key, collect signatures, or request access to your devices. The illustrations use sample data only.',
  },
];

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
            <Image src="/vow-glyph.png" alt="" width={36} height={31} />
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
        <Image src="/vow-mark.png" alt="Vow app icon" width={72} height={72} />
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
