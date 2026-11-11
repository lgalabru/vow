'use client';

import { Inbox, LayoutGrid, ListChecks, ShieldCheck, Users } from 'lucide-react';
import { motion, useReducedMotion, useScroll, useTransform } from 'motion/react';
import Image from 'next/image';
import { useLayoutEffect, useRef, useState } from 'react';
import type { Act } from '../stageshow/kit/act';
import { Button } from '../stageshow/kit/controls/Button';
import { Check } from '../stageshow/kit/parts/Check';
import { Stage } from '../stageshow/kit/stage';
import { Window } from '../stageshow/kit/window';
import { Reveal } from './site';
import './mac.css';

// One still of the Mac companion at the end of a ceremony, with one beat: the
// confirmation ticks as the section scrolls in. The window is the only one on
// the page; it enters from the tile's top-left gutter and runs off the other
// two edges.

const points = [
  {
    title: 'Enrolled in person.',
    body: 'Each member binds their iPad’s key to their identity once. New projects never repeat it.',
  },
  {
    title: 'Quorums you can reuse.',
    body: 'Name a set of members and a threshold, such as two of three, and use it across projects.',
  },
  {
    title: 'Keys in the Secure Enclave.',
    body: 'On Mac as on iPad, Vow’s device key is created in the Secure Enclave. It can sign, and it cannot be copied off.',
  },
  {
    title: 'One fingerprint to compare.',
    body: 'Everyone checks the same team, members and threshold before the ceremony is exported.',
  },
];

const NAV = [
  { group: 'Ceremony' },
  { label: 'Overview', icon: LayoutGrid },
  { label: 'Members', icon: Users },
  { label: 'Safeguards', icon: ShieldCheck },
  { label: 'Review ceremony', icon: ListChecks, selected: true },
  { group: 'Workspace' },
  { label: 'Requests', icon: Inbox },
];

type Beat = { on: boolean };
const script = async (a: Act<Beat>) => {
  await a.wait(700);
  await a.set({ on: true });
};

const on = (value: boolean) => (value ? '' : undefined);

function Ceremony({ confirmed, wide }: { confirmed: boolean; wide: boolean }) {
  const content = (
    <div className="mac-review">
      <div className="mac-team">Treasury team</div>
      <div className="mac-title">Your rehearsal is complete</div>
      <div className="mac-sub">
        Make sure everyone sees the same team, members, and approval threshold.
      </div>
      <div className="mac-group">
        <div className="mac-line">
          <span>Team</span>
          <b>Treasury team</b>
        </div>
        <div className="mac-line">
          <span>Members</span>
          <b>3</b>
        </div>
        <div className="mac-line">
          <span>Required approvals</span>
          <b>2</b>
        </div>
      </div>
      <div className="mac-group mac-group--print">
        <span>Package fingerprint</span>
        <code>2c5756b033df853918c4eac6de71ef13ecc68985761c94720f289920abdb2bd2</code>
      </div>
      <div className="mac-confirm" data-on={on(confirmed)}>
        <Check on={confirmed} pending size={18} />
        Rehearsal confirmed
      </div>
      <Button variant="primary" size="large" className="mac-export">
        Export Ceremony…
      </Button>
    </div>
  );
  if (!wide) {
    return (
      <Window title="Review ceremony" className="mac-window" body={{ 'data-crop': '' }}>
        {content}
      </Window>
    );
  }
  return (
    <Window
      title="Review ceremony"
      className="mac-window"
      body={{ 'data-crop': '' }}
      sidebarWidth={220}
      sidebar={
        <nav className="mac-side">
          <Image className="mac-side-mark" src="/vow-mark.png" alt="" width={36} height={36} />
          <div className="mac-side-name">Vow</div>
          {NAV.map((item) =>
            'group' in item ? (
              <span key={item.group} className="mac-side-group">
                {item.group}
              </span>
            ) : (
              <span key={item.label} className="mac-side-row" data-selected={on(!!item.selected)}>
                <item.icon size={16} strokeWidth={1.8} />
                {item.label}
              </span>
            ),
          )}
        </nav>
      }
    >
      {content}
    </Window>
  );
}

/** The Mac companion: the in-person ceremony that enrolls a team before anyone approves. */
export function MacCompanion() {
  const tile = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotion();
  // Zero until measured, so the stage is never drawn at a guessed width and then resized.
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const node = tile.current;
    if (!node) return;
    const measure = () => setWidth(Math.max(1, Math.round(node.getBoundingClientRect().width)));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const { scrollYProgress } = useScroll({ target: tile, offset: ['start end', 'end start'] });
  const y = useTransform(scrollYProgress, [0, 1], [48, -48]);
  const wide = width >= 720;

  return (
    <section className="section shell" id="mac" aria-labelledby="mac-heading">
      <Reveal className="heading">
        <p className="tag">Mac companion</p>
        <h2 id="mac-heading">
          The ceremony
          <br />
          happens on the Mac.
        </h2>
        <p>
          Before anyone approves anything, the team meets once. The Mac companion enrolls each
          member&rsquo;s iPad and security key, sets how many approvals a quorum needs, and exports
          the result for everyone to compare.
        </p>
      </Reveal>

      <div ref={tile} className="mac-tile" aria-hidden>
        {width > 0 && (
          <motion.div className="mac-picture" style={reduced ? undefined : { y }}>
            <Stage<Beat>
              width={width}
              height={wide ? 560 : 520}
              initial={{ on: false }}
              poster={{ on: true }}
              play="once"
              script={script}
              className="mac-stage"
            >
              {(scene) => <Ceremony confirmed={scene.on} wide={wide} />}
            </Stage>
          </motion.div>
        )}
      </div>

      <ul className="mac-points">
        {points.map((point, index) => (
          <li key={point.title}>
            <Reveal delay={index * 0.08}>
              <h3>{point.title}</h3>
              <p>{point.body}</p>
            </Reveal>
          </li>
        ))}
      </ul>
    </section>
  );
}
