'use client';

import { FileCheck2, Lock, Wifi } from 'lucide-react';
import { motion, useReducedMotion, useScroll, useTransform } from 'motion/react';
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import type { Act } from '../stageshow/kit/act';
import { Badge } from '../stageshow/kit/controls/Badge';
import { Toggle } from '../stageshow/kit/controls/Toggle';
import { States } from '../stageshow/kit/motion/States';
import { Avatar } from '../stageshow/kit/parts/Avatar';
import { Check } from '../stageshow/kit/parts/Check';
import { Icon } from '../stageshow/kit/parts/Icon';
import { Row } from '../stageshow/kit/parts/Row';
import { Stage } from '../stageshow/kit/stage';
import { SquadsLogo } from './squads';
import { Bar } from '../stageshow/kit/window';
import './bento.css';

// The tile list, written before any tile was built (Stageshow, bento.md):
//
//   Tile     Span   Kind       The one thing                      Moves
//   Offline  4 x 1  Hero UI    Wi-Fi goes off, approval unlocks   the switch, then the status
//   Quorum   2 x 1  Stat       2 of 3, on the one dark tile       the arc draws in
//   Squads   2 x 1  Statement  the Squads mark                    -
//   Review   4 x 1  Component  one request, decoded               -
//   File     3 x 1  Object     the approval as a file             rises out of the crop
//   Team     3 x 1  Component  three members, one still pending   a second tick lands
//
// Six columns, so the rows split 4/2, 2/4 and 3/3 and no two rows share a
// seam. Each picture is its own Stage at 1:1; the ones that move play one
// beat, once, as the grid scrolls in.

const STEP = 110;
const LEAD = 450;

type Beat = { on: boolean };
const before: Beat = { on: false };
const after: Beat = { on: true };
const beat = (index: number) => async (a: Act<Beat>) => {
  await a.wait(LEAD + index * STEP);
  await a.set({ on: true });
};
const scripts = [0, 1, 2, 3, 4, 5].map(beat);

const on = (value: boolean) => (value ? '' : undefined);

/** The tile owns the crop, so each stage is drawn at its tile's own width. */
function usePictureWidth() {
  const ref = useRef<HTMLDivElement>(null);
  // Zero until measured, so a stage is never drawn at a guessed width and then resized.
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const node = ref.current;
    if (!node) return;
    const measure = () => setWidth(Math.max(1, Math.round(node.getBoundingClientRect().width)));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  return [ref, width] as const;
}

function useSeen<T extends Element>(delay: number) {
  const ref = useRef<T>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    let timer = 0;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        timer = window.setTimeout(() => setSeen(true), delay);
      },
      { threshold: 0.4 },
    );
    observer.observe(node);
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
    };
  }, [delay]);
  return [ref, seen] as const;
}

/** True once the grid is wide enough for its three-column layout; stacked tiles hold still. */
function useColumns() {
  const [columns, setColumns] = useState(false);
  useEffect(() => {
    const query = window.matchMedia('(min-width: 1000px)');
    const update = () => setColumns(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);
  return columns;
}

function Tile({
  area,
  lead,
  children,
  picture,
  dark,
  drift = 0,
}: {
  area: string;
  lead?: string;
  children?: ReactNode;
  picture?: ReactNode;
  dark?: boolean;
  /** How far below its place this tile starts, in px, for the staggered parallax. */
  drift?: number;
}) {
  const ref = useRef<HTMLElement>(null);
  const reduced = useReducedMotion();
  const columns = useColumns();
  // Each tile starts lower than its neighbors and settles as it comes up the screen.
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'start 0.4'] });
  const y = useTransform(scrollYProgress, [0, 1], [drift, 0]);
  return (
    <motion.section
      ref={ref}
      className={`vb-tile vb-tile--${area}`}
      data-dark={on(!!dark)}
      style={reduced || !drift || !columns ? undefined : { y }}
    >
      {lead ? (
        <p className="vb-copy">
          <b>{lead}</b> {children}
        </p>
      ) : (
        children
      )}
      {picture}
    </motion.section>
  );
}

function Offline() {
  const [picture, width] = usePictureWidth();
  return (
    <Tile
      area="offline"
      lead="Offline means offline."
      picture={
        <div ref={picture} className="vb-picture" aria-hidden>
          {width > 0 && (
            <Stage<Beat>
              width={width}
              height={252}
              initial={before}
              poster={after}
              play="once"
              script={scripts[0]}
              className="vb-stage"
            >
              {(scene) => (
                <div className="vb-panel vb-panel--large">
                  <Row
                    lead={
                      <span className="vb-glyph" data-on={on(!scene.on)}>
                        <Wifi size={22} strokeWidth={2} />
                      </span>
                    }
                    title={<span className="vb-name">Wi-Fi</span>}
                    pad={width < 480 ? 12 : 20}
                  >
                    <Toggle on={!scene.on} />
                  </Row>
                  <Row
                    lead={
                      <span className="vb-glyph" data-on={on(scene.on)} data-tone="success">
                        <Lock size={22} strokeWidth={2} />
                      </span>
                    }
                    title={<span className="vb-name">Approval</span>}
                    pad={width < 480 ? 12 : 20}
                  >
                    <States
                      value={scene.on ? 'ready' : 'paused'}
                      align="end"
                      states={{
                        paused: (
                          <Badge tone="warning">
                            {width < 480 ? 'Paused' : 'Paused while online'}
                          </Badge>
                        ),
                        ready: (
                          <Badge tone="success" icon={<Icon name="check" size={12} />}>
                            Ready
                          </Badge>
                        ),
                      }}
                    />
                  </Row>
                </div>
              )}
            </Stage>
          )}
        </div>
      }
    >
      Vow pauses approval the moment it detects a network, and shows you why.
    </Tile>
  );
}

function Quorum() {
  const reduced = useReducedMotion();
  const [ref, seen] = useSeen<HTMLDivElement>(LEAD + STEP);
  return (
    <Tile area="quorum" dark>
      <div ref={ref} className="vb-quorum" data-on={on(seen || !!reduced)}>
        <span className="vb-ring">
          <svg viewBox="0 0 120 120" aria-hidden>
            <circle cx="60" cy="60" r="52" />
            <circle className="vb-ring-arc" cx="60" cy="60" r="52" pathLength={1} />
          </svg>
          <span className="vb-ring-number">2/3</span>
        </span>
        <span className="vb-quorum-label">Approvals collected</span>
        <span className="vb-quorum-note">Each one from its own iPad.</span>
      </div>
    </Tile>
  );
}

const MEMBERS = ['Ana Ruiz', 'Kenji Mori', 'Priya Shah'];

function Team() {
  const [picture, width] = usePictureWidth();
  return (
    <Tile
      area="team"
      drift={72}
      lead="Everyone signs for themselves."
      picture={
        <div ref={picture} className="vb-picture" aria-hidden>
          {width > 0 && (
            <Stage<Beat>
              width={width}
              height={240}
              initial={before}
              poster={after}
              play="once"
              script={scripts[2]}
              className="vb-stage"
            >
              {(scene) => (
                <div className="vb-panel">
                  {MEMBERS.map((name, index) => (
                    <Row
                      key={name}
                      lead={<Avatar name={name} size={32} />}
                      title={<span className="vb-name">{name}</span>}
                      pad={14}
                    >
                      <Check on={index === 0 || (index === 1 && scene.on)} pending size={22} />
                    </Row>
                  ))}
                </div>
              )}
            </Stage>
          )}
        </div>
      }
    >
      No shared device, no shared key.
    </Tile>
  );
}

function File() {
  return (
    <Tile
      area="file"
      drift={40}
      lead="Moves as a file."
      picture={
        <div className="vb-picture vb-picture--center" aria-hidden>
          <Stage<Beat>
            width={360}
            height={216}
            initial={before}
            poster={after}
            play="once"
            script={scripts[3]}
            className="vb-stage"
          >
            {(scene) => (
              <div className="vb-file" data-on={on(scene.on)}>
                <FileCheck2 size={30} strokeWidth={1.6} />
                <span className="vb-file-name">contributor-grants.vow</span>
                <span className="vb-file-hash">6f70 1b42 aafa 7b73</span>
                {[150, 112, 168, 96].map((w) => (
                  <Bar key={w} w={w} h={6} tone={2} />
                ))}
              </div>
            )}
          </Stage>
        </div>
      }
    >
      Requests in, approvals out. Nothing travels over a network.
    </Tile>
  );
}

function Squads() {
  return (
    <Tile
      area="squads"
      drift={40}
      lead="Designed for Squads multisig."
      picture={
        <span className="vb-squads">
          <SquadsLogo height={34} />
        </span>
      }
    >
      Approvals are shaped for Squads proposals. The on-chain adapter is still in development.
    </Tile>
  );
}

function Review() {
  const [picture, width] = usePictureWidth();
  return (
    <Tile
      area="review"
      drift={72}
      lead="Read what you approve."
      picture={
        <div ref={picture} className="vb-picture" aria-hidden>
          {width > 0 && (
            <Stage width={width} height={236} className="vb-stage">
              {() => (
                <div className="vb-panel vb-request">
                  <div className="vb-request-head">
                    <span className="vb-name">Contributor grants</span>
                    <span className="vb-amount">12,500.00 USDC</span>
                  </div>
                  <Row title={<span className="vb-name vb-name--quiet">From</span>} pad={14}>
                    <span className="vb-name">Treasury</span>
                  </Row>
                  <Row title={<span className="vb-name vb-name--quiet">To</span>} pad={14}>
                    <span className="vb-name">Grants</span>
                  </Row>
                </div>
              )}
            </Stage>
          )}
        </div>
      }
    >
      Requests arrive as files. The iPad shows who pays whom, and how much, before it asks you for
      anything.
    </Tile>
  );
}

/** The features grid: six tiles of three sizes. */
export function Bento() {
  return (
    <div className="vb">
      <div className="vb-grid">
        <Offline />
        <Quorum />
        <Squads />
        <Review />
        <File />
        <Team />
      </div>
    </div>
  );
}
