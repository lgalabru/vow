'use client';

import { FileCheck2, Fingerprint, KeyRound, Lock, Plus, Wifi } from 'lucide-react';
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
import { Bar } from '../stageshow/kit/window';
import './bento.css';

// The tile list, written before any tile was built (Stageshow, bento.md):
//
//   Tile     Span   Kind       The one thing                      Moves
//   Offline  2 x 1  Hero UI    Wi-Fi goes off, approval unlocks   the switch, then the status
//   Quorum   1 x 1  Stat       2 of 3, on the one dark tile       the arc draws in
//   Team     1 x 1  Component  three members, one still pending   a second tick lands
//   File     1 x 1  Object     the approval as a file             rises out of the crop
//   Proofs   1 x 1  Diagram    device key plus security key       both confirm
//
// Each picture is its own Stage at 1:1 and plays one beat, once, as the grid
// scrolls in, in reading order.

const STEP = 110;
const LEAD = 450;

type Beat = { on: boolean };
const before: Beat = { on: false };
const after: Beat = { on: true };
const beat = (index: number) => async (a: Act<Beat>) => {
  await a.wait(LEAD + index * STEP);
  await a.set({ on: true });
};
const scripts = [0, 1, 2, 3, 4].map(beat);

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
      drift={40}
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
      drift={96}
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

function Proofs() {
  return (
    <Tile
      area="proofs"
      drift={64}
      lead="Two proofs, every time."
      picture={
        <div className="vb-picture vb-picture--center" aria-hidden>
          <Stage<Beat>
            width={360}
            height={216}
            initial={before}
            poster={after}
            play="once"
            script={scripts[4]}
            className="vb-stage"
          >
            {(scene) => (
              <div className="vb-proofs" data-on={on(scene.on)}>
                <span className="vb-proof-slot">
                  <span className="vb-proof">
                    <Fingerprint size={34} strokeWidth={1.6} />
                  </span>
                  <Check on={scene.on} size={24} className="vb-proof-check" />
                </span>
                <Plus size={20} strokeWidth={2} className="vb-proof-plus" />
                <span className="vb-proof-slot">
                  <span className="vb-proof">
                    <KeyRound size={34} strokeWidth={1.6} />
                  </span>
                  <Check on={scene.on} size={24} className="vb-proof-check" />
                </span>
              </div>
            )}
          </Stage>
        </div>
      }
    >
      Your iPad&rsquo;s protected key, and a security key you touch.
    </Tile>
  );
}

/** The features grid: five tiles, hero and strip. */
export function Bento() {
  return (
    <div className="vb">
      <div className="vb-grid">
        <Offline />
        <Quorum />
        <Team />
        <File />
        <Proofs />
      </div>
    </div>
  );
}
