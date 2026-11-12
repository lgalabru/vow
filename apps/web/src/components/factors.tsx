'use client';

import { BadgeCheck, BatteryFull, Fingerprint, KeyRound, WifiOff } from 'lucide-react';
import {
  MotionConfig,
  motion,
  useMotionValueEvent,
  useReducedMotion,
  useScroll,
  useTransform,
  type MotionValue,
} from 'motion/react';
import { useRef, useState } from 'react';
import { Check } from '../stageshow/kit/parts/Check';
import { Spinner } from '../stageshow/kit/parts/Spinner';
import { Stage } from '../stageshow/kit/stage';
import { Bento } from './bento';
import { IPadFrame } from './device';
import { MacCompanion } from './mac';
import { Closing, Footer, Header, Questions, Reveal } from './site';
import './factors.css';

// The story, written before it was built. One tall section, one pinned iPad,
// and the page's scroll is the clock:
//
//   Scroll     Chapter           On the iPad                   Around it
//   0.00-0.30  Factor 1, hand    the signature draws           -
//   0.30-0.58  Factor 2, key     "Touch your security key"     the key slides into the port
//   0.58-0.84  Factor 3, finger  "Confirm with Touch ID"       the top button lights
//   0.84-1.00  Approval ready    three ticks, the seal         -
//
// Three layers move at their own speed: the copy, the iPad and the security key.

const AT = {
  signStart: 0.05,
  signEnd: 0.24,
  signed: 0.26,
  key: 0.3,
  plugged: 0.44,
  keyed: 0.52,
  touch: 0.58,
  touched: 0.74,
  ready: 0.84,
};

const chapters = [
  {
    kicker: 'Factor 1 · Your hand',
    title: 'Sign it yourself.',
    body: 'Write your signature on the request with Apple Pencil or a finger. It records that you read it and meant it.',
  },
  {
    kicker: 'Factor 2 · Your key',
    title: 'Plug in. Touch.',
    body: 'A registered USB-C security key adds its own cryptographic proof, behind the key’s PIN and a touch.',
  },
  {
    kicker: 'Factor 3 · Your fingerprint',
    title: 'Rest a finger.',
    body: 'Touch ID unlocks the signing key held in this iPad’s Secure Enclave. It never leaves the device.',
  },
  {
    kicker: 'Approval ready',
    title: 'Three factors. One approval.',
    body: 'Verified on the iPad and exported as a file for your team to collect. Nothing went over a network.',
  },
];

const factors = ['Signature', 'Security key', 'Touch ID'];

/** The progress rail: one segment per factor, filled over the stretch of scroll it covers. */
const rail: { label: string; from: number; to: number }[] = [
  { label: 'Signature', from: AT.signStart, to: AT.signed },
  { label: 'Security key', from: AT.key, to: AT.keyed },
  { label: 'Touch ID', from: AT.touch, to: AT.touched },
];

type Moment = {
  chapter: number;
  signed: boolean;
  keyIn: boolean;
  plugged: boolean;
  keyed: boolean;
  touched: boolean;
};

const momentAt = (p: number): Moment => ({
  chapter: p < AT.key ? 0 : p < AT.touch ? 1 : p < AT.ready ? 2 : 3,
  signed: p >= AT.signed,
  keyIn: p >= AT.key - 0.03,
  plugged: p >= AT.plugged,
  keyed: p >= AT.keyed,
  touched: p >= AT.touched,
});

const same = (a: Moment, b: Moment) =>
  (Object.keys(a) as (keyof Moment)[]).every((key) => a[key] === b[key]);

const on = (value: boolean) => (value ? '' : undefined);

function Screen({ moment, ink }: { moment: Moment; ink: MotionValue<number> }) {
  const { chapter, signed, plugged, keyed, touched } = moment;
  return (
    <div className="fx-screen">
      <div className="fx-status">
        <span>9:41</span>
        <span className="fx-status-title">Your approval</span>
        <BatteryFull size={20} strokeWidth={1.6} />
      </div>

      <div className="fx-body">
        <div className="fx-focus">
          <div className="fx-view" data-show={on(chapter === 0)}>
            <div className="fx-pad">
              <span className="fx-pad-what">Contributor grants · 12,500.00 USDC</span>
              <svg viewBox="10 6 230 72">
                <motion.path
                  style={{ pathLength: ink }}
                  d="M14 60C30 22 48 8 53 32c4 24-18 42-23 27-4-14 28-30 43-16 9 9 3 19 11 13 9-8 13-21 20-10 4 8 0 16 10 8 10-10 14-14 20-4 4 8 16 4 34-10 12-8 32 4 66-6"
                />
              </svg>
            </div>
          </div>
          <div className="fx-view" data-show={on(chapter === 1)}>
            <span className="fx-disc" data-on={on(keyed)}>
              <KeyRound size={30} strokeWidth={1.6} />
            </span>
            <div className="fx-prompt">
              {keyed
                ? 'Security key verified'
                : plugged
                  ? 'Touch your security key'
                  : 'Insert your security key'}
            </div>
            <span className="fx-wait" data-show={on(plugged && !keyed)}>
              <Spinner size={16} />
            </span>
          </div>
          <div className="fx-view" data-show={on(chapter === 2)}>
            <span className="fx-disc" data-on={on(touched)}>
              <Fingerprint size={32} strokeWidth={1.5} />
            </span>
            <div className="fx-prompt">
              {touched ? 'Touch ID confirmed' : 'Confirm with Touch ID'}
            </div>
            <span className="fx-hint" data-show={on(!touched)}>
              Rest your finger on the top button
            </span>
          </div>
          <div className="fx-view" data-show={on(chapter === 3)}>
            <BadgeCheck className="fx-seal" size={56} strokeWidth={1.5} />
            <div className="fx-prompt fx-prompt--large">Approval ready</div>
            <span className="fx-hint" data-show>
              Verified locally
            </span>
          </div>
        </div>

        <div className="fx-side">
          {/* The connection status never leaves the screen */}
          <div className="fx-network" data-offline>
            <span className="fx-network-glyph">
              <WifiOff size={16} strokeWidth={2} />
            </span>
            <span>
              <b>Offline</b>
              <span>Ready to approve</span>
            </span>
          </div>
          <div className="fx-list">
            {factors.map((label, index) => {
              const done = [signed, keyed, touched][index];
              return (
                <div key={label} className="fx-row" data-done={on(done)}>
                  <span>{label}</span>
                  <Check on={done} pending={chapter === index} size={20} />
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

function RailStep({
  p,
  step,
  active,
}: {
  p: MotionValue<number>;
  step: (typeof rail)[number];
  active: boolean;
}) {
  const fill = useTransform(p, [step.from, step.to], [0, 1], { clamp: true });
  return (
    <li data-active={on(active)}>
      <span className="fx-rail-track">
        <motion.span style={{ scaleX: fill }} />
      </span>
      {step.label}
    </li>
  );
}

function Story() {
  const ref = useRef<HTMLElement>(null);
  const reduced = useReducedMotion();
  const { scrollYProgress: p } = useScroll({ target: ref, offset: ['start start', 'end end'] });
  const [moment, setMoment] = useState<Moment>(momentAt(0));
  useMotionValueEvent(p, 'change', (value) => {
    const next = momentAt(value);
    setMoment((current) => (same(current, next) ? current : next));
  });

  const ink = useTransform(p, [AT.signStart, AT.signEnd], [0, 1], { clamp: true });
  // The key comes in from past the edge of the page and seats in the port.
  const keyX = useTransform(p, [AT.key - 0.02, AT.plugged], [720, 0], { clamp: true });
  const deviceY = useTransform(p, [0, 1], [16, -16]);
  const { chapter } = moment;

  return (
    <section ref={ref} className="fx-story" id="ipad" aria-labelledby="story-heading">
      <h2 id="story-heading" className="fx-sr">
        3-factor authentication on the iPad, step by step
      </h2>
      <div className="fx-pin">
        <div className="fx-copy">
          <div className="fx-chapters">
            {chapters.map((item, index) => (
              <article key={item.kicker} className="fx-chapter" data-show={on(chapter === index)}>
                <p className="tag">{item.kicker}</p>
                <h3>{item.title}</h3>
                <p>{item.body}</p>
              </article>
            ))}
          </div>
        </div>

        <motion.div className="fx-device" style={reduced ? undefined : { y: deviceY }}>
          <IPadFrame
            label="An iPad mini running Vow, offline. A sample request collects a handwritten signature, a security key touch and Touch ID."
            around={
              <>
                <span
                  className="fx-touch"
                  data-show={on(chapter === 2)}
                  data-done={on(moment.touched)}
                />
                <motion.span
                  className="fx-key"
                  style={{ x: keyX }}
                  data-show={on(moment.keyIn)}
                  aria-hidden
                >
                  <span className="fx-key-plug" />
                  <span className="fx-key-body">
                    <span className="fx-key-disc" data-on={on(moment.keyed)} />
                    <span className="fx-key-hole" />
                  </span>
                </motion.span>
              </>
            }
          >
            <Stage width={520} height={341} className="fx-stage" fill unframed>
              {() => <Screen moment={moment} ink={ink} />}
            </Stage>
          </IPadFrame>
        </motion.div>

        <ol className="fx-rail" aria-hidden>
          {rail.map((step, index) => (
            <RailStep key={step.label} p={p} step={step} active={chapter === index} />
          ))}
        </ol>
      </div>
    </section>
  );
}

function Hero() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] });
  const y = useTransform(scrollYProgress, [0, 1], [0, 160]);
  return (
    <section ref={ref} className="hero fx-hero" aria-labelledby="hero-heading">
      <motion.div className="hero-copy shell" style={{ y }}>
        <p className="tag">An offline signer for iPad</p>
        <h1 id="hero-heading">
          3-Factor
          <br />
          <span>Authentication.</span>
        </h1>
        <p className="lead">
          Your signature, your security key and your fingerprint. Vow asks for all three before an
          approval leaves your iPad, and only while the iPad is offline.
        </p>
        <ul className="fx-factors">
          {factors.map((label, index) => (
            <li key={label}>
              <span>{index + 1}</span>
              {label}
            </li>
          ))}
        </ul>
      </motion.div>
    </section>
  );
}

const links = [
  { href: '#ipad', label: 'iPad' },
  { href: '#features', label: 'Features' },
  { href: '#mac', label: 'Mac' },
  { href: '#questions', label: 'Questions' },
];

/** The public product page, with no account collection or third-party analytics. */
export function FactorsSite({ stars }: { stars?: number | null }) {
  return (
    <MotionConfig reducedMotion="user">
      <Header stars={stars} links={links} />
      <main id="main">
        <Hero />
        <Story />
        <p className="fx-note shell">Illustration with sample data. No signing keys are used.</p>
        <section className="section shell" id="features" aria-labelledby="features-heading">
          <Reveal className="heading">
            <h2 id="features-heading">
              An offline
              <br />
              signing station.
            </h2>
            <p>
              Vow turns an iPad mini into the one place your team approves from. Doing it through an
              app is what makes the rest possible.
            </p>
          </Reveal>
          <Bento />
        </section>
        <MacCompanion />
        <Questions />
        <Closing />
      </main>
      <Footer />
    </MotionConfig>
  );
}
