'use client';

import {
  BadgeCheck,
  BatteryFull,
  Clock,
  Inbox,
  Info,
  KeyRound,
  Share,
  Signature,
  TabletSmartphone,
  Users,
  WifiOff,
} from 'lucide-react';
import Image from 'next/image';
import { useMemo, useState, type ReactNode } from 'react';
import type { Act } from '../stageshow/kit/act';
import { Button } from '../stageshow/kit/controls/Button';
import { States } from '../stageshow/kit/motion/States';
import { Spinner } from '../stageshow/kit/parts/Spinner';
import { Stage } from '../stageshow/kit/stage';
import './device.css';

/** Fictional requests. The page never reads a wallet, a key or a real multisig. */
const REQUESTS = [
  {
    title: 'Contributor grants',
    summary: 'November grants for open-source contributors.',
    amount: '12,500.00 USDC',
    from: 'Treasury',
    to: 'Grants',
  },
  {
    title: 'Audit retainer',
    summary: 'Second milestone of the security review.',
    amount: '8,000.00 USDC',
    from: 'Treasury',
    to: 'Security',
  },
];

type Scene = {
  sheet: boolean;
  signed: boolean;
  auth: 'idle' | 'key' | 'done';
  view: 'sign' | 'ready';
  leaving: boolean;
  entering: boolean;
};

const initial: Scene = {
  sheet: false,
  signed: false,
  auth: 'idle',
  view: 'sign',
  leaving: false,
  entering: false,
};

/** The frame most people see: reduced motion, thumbnails and screenshots. */
const poster: Scene = { ...initial, sheet: true, signed: true, auth: 'done', view: 'ready' };

const NAV = [
  { label: 'Requests', icon: Inbox, selected: true },
  { label: 'History', icon: Clock },
  { label: 'Your team', icon: Users },
  { label: 'This iPad', icon: TabletSmartphone },
];

const on = (value: boolean) => (value ? '' : undefined);

function Screen({ scene, index, portrait }: { scene: Scene; index: number; portrait: boolean }) {
  const request = REQUESTS[index % REQUESTS.length];
  return (
    <div className="vw-screen" data-portrait={on(portrait)}>
      <div className="vw-status">
        <span>9:41</span>
        <span className="vw-status-date">Tue Nov 10</span>
        <BatteryFull size={24} strokeWidth={1.6} />
      </div>

      {!portrait && (
        <aside className="vw-side">
          <Image className="vw-side-mark" src="/vow-icon.png" alt="" width={48} height={48} />
          <div className="vw-side-name">Vow</div>
          <div className="vw-side-team">Treasury team</div>
          <nav className="vw-nav">
            {NAV.map(({ label, icon: Glyph, selected }) => (
              <span key={label} className="vw-nav-row" data-selected={on(!!selected)}>
                <Glyph size={22} strokeWidth={1.7} />
                {label}
              </span>
            ))}
          </nav>
          <span className="vw-pill">
            <WifiOff size={16} strokeWidth={2} />
            Offline
          </span>
        </aside>
      )}

      <main className="vw-main">
        <div className="vw-bar">
          Requests
          {portrait && (
            <span className="vw-pill">
              <WifiOff size={16} strokeWidth={2} />
              Offline
            </span>
          )}
        </div>
        <div
          className="vw-request"
          data-leaving={on(scene.leaving)}
          data-entering={on(scene.entering)}
        >
          <div className="vw-meta">
            <span>Sample request</span>
            <span>
              {(index % REQUESTS.length) + 1} of {REQUESTS.length}
            </span>
          </div>
          <div className="vw-title">{request.title}</div>
          <div className="vw-summary">{request.summary}</div>
          <div className="vw-group">
            <div className="vw-line">
              <span>Amount</span>
              <b>{request.amount}</b>
            </div>
            <div className="vw-line">
              <span>From</span>
              <b>{request.from}</b>
            </div>
            <div className="vw-line">
              <span>To</span>
              <b>{request.to}</b>
            </div>
            <div className="vw-line">
              <span>Approvals needed</span>
              <b>2 of 3</b>
            </div>
          </div>
          <div className="vw-note">
            <Info size={20} strokeWidth={1.7} />
            <b>A safe place to try it</b>
            <span>This is a sample, not a Solana transaction. It cannot move funds.</span>
          </div>
        </div>
        <div className="vw-actions">
          <Button className="vw-button vw-button--tint">Decline</Button>
          <Button
            className="vw-button vw-button--fill"
            data-target="approve"
            icon={<Signature size={22} strokeWidth={1.8} />}
          >
            Review &amp; Approve
          </Button>
        </div>
      </main>

      <div className="vw-scrim" data-show={on(scene.sheet)} />
      <div className="vw-sheet" data-show={on(scene.sheet)}>
        <div className="vw-view" data-show={on(scene.view === 'sign')}>
          <div className="vw-sheet-bar">
            <span className="vw-chip">Cancel</span>
            <span className="vw-sheet-title">Your approval</span>
          </div>
          <div className="vw-group vw-group--row">
            <div className="vw-line">
              <span>{request.title}</span>
              <b>{request.amount}</b>
            </div>
          </div>
          <div className="vw-label">Your signature</div>
          <div className="vw-pad" data-signed={on(scene.signed)}>
            <div className="vw-pad-ink">
              <svg viewBox="10 6 230 72" preserveAspectRatio="none" aria-hidden>
                <path
                  pathLength={1}
                  d="M14 60C30 22 48 8 53 32c4 24-18 42-23 27-4-14 28-30 43-16 9 9 3 19 11 13 9-8 13-21 20-10 4 8 0 16 10 8 10-10 14-14 20-4 4 8 16 4 34-10 12-8 32 4 66-6"
                />
              </svg>
              <span className="vw-pad-hint">Sign with Apple Pencil or your finger</span>
            </div>
          </div>
          <Button
            className="vw-button vw-button--fill vw-button--wide"
            data-target="authorize"
            data-ready={on(scene.signed)}
            icon={
              <States
                value={scene.auth === 'idle' ? 'idle' : 'key'}
                states={{
                  idle: <KeyRound size={22} strokeWidth={1.8} />,
                  key: <Spinner size={22} />,
                }}
              />
            }
          >
            {scene.auth === 'idle' ? 'Authorize with security key' : 'Touch your security key'}
          </Button>
        </div>

        <div className="vw-view vw-view--ready" data-show={on(scene.view === 'ready')}>
          <BadgeCheck className="vw-seal" size={64} strokeWidth={1.5} />
          <div className="vw-ready-title">Approval ready</div>
          <div className="vw-ready-sub">Share it with your team.</div>
          <div className="vw-group">
            <div className="vw-line">
              <span>Request</span>
              <b>{request.title}</b>
            </div>
            <div className="vw-line">
              <span>Signature</span>
              <b>Verified locally</b>
            </div>
          </div>
          <Button
            className="vw-button vw-button--fill vw-button--wide"
            icon={<Share size={20} strokeWidth={1.8} />}
          >
            Share Approval
          </Button>
          <span className="vw-text-button" data-target="done" data-cursor="pointer">
            Done
          </span>
        </div>
      </div>
    </div>
  );
}

/**
 * A scripted illustration of one approval on an iPad mini: review, handwritten
 * consent, security key, a portable approval. The frame is drawn in CSS at the
 * device's real proportions; the screen is a Stageshow stage.
 */
export function Device({ portrait = false }: { portrait?: boolean }) {
  const [index, setIndex] = useState(0);
  const script = useMemo(
    () => async (a: Act<Scene>) => {
      await a.wait(1500);
      await a.click('approve');
      await a.set({ sheet: true });
      await a.wait(1000);
      await a.set({ signed: true });
      await a.wait(2100);
      await a.click('authorize');
      await a.set({ auth: 'key' });
      await a.wait(1800);
      await a.set({ auth: 'done', view: 'ready' });
      await a.wait(2800);
      await a.click('done');
      await a.set({ sheet: false });
      await a.wait(520);
      // The approved request leaves the queue and the next one takes its place.
      await a.set({ leaving: true });
      await a.wait(360);
      setIndex((n) => n + 1);
      await a.snap({ ...initial, entering: true });
      await a.set({ entering: false });
      await a.wait(700);
    },
    [],
  );
  const size = portrait ? { width: 520, height: 792 } : { width: 1133, height: 744 };
  return (
    <IPadFrame
      portrait={portrait}
      label="An iPad mini running Vow. A sample request is reviewed, signed by hand, authorized with a security key and exported as an approval."
    >
      <Stage<Scene>
        key={portrait ? 'portrait' : 'landscape'}
        {...size}
        initial={initial}
        poster={poster}
        script={script}
        play="loop"
        cursor={{ at: 'approve', style: 'touch' }}
        className="vw-stage"
        unframed
      >
        {(scene) => <Screen scene={scene} index={index} portrait={portrait} />}
      </Stage>
    </IPadFrame>
  );
}

/**
 * An iPad mini drawn in CSS at the device's real proportions. `children` is the
 * screen; `around` holds anything attached to the body, such as a security key.
 */
export function IPadFrame({
  portrait = false,
  label,
  children,
  around,
}: {
  portrait?: boolean;
  label: string;
  children: ReactNode;
  around?: ReactNode;
}) {
  return (
    <div className="vw-ipad" data-portrait={on(portrait)} role="img" aria-label={label}>
      {around}
      <div className="vw-ipad-glass" aria-hidden>
        {children}
      </div>
    </div>
  );
}
