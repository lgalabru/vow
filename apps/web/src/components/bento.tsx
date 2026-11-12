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

// The tile list, written before any tile was built (Stageshow, bento.md). It
// follows the pitch: an iPad as an offline signing station, and what the app
// adds on top.
//
//   Tile      Span   Kind        The one thing                        Moves
//   Offline   4 x 1  Hero UI     Wi-Fi goes off, approval unlocks     the switch, then the status
//   Station   2 x 1  Statement   nothing else runs here, on the dark  -
//   Squads    2 x 1  Statement   the Squads mark                      -
//   Explain   4 x 1  Component   one request, put in plain words      the explanation arrives
//   File      3 x 1  Object      the request as a file                rises out of the crop
//   Team      3 x 1  Component   three members, one still pending     a second tick lands
//   Replay    4 x 1  Component   the accounts, replayed offline       the result ticks
//   Evidence  2 x 1  Collection  which iPad, which key, which member  -
//
// Six columns, so the rows split 4/2, 2/4, 3/3 and 4/2 and no row shares a
// seam with the one above. Each picture is its own Stage at 1:1; the ones
// that move play one beat, once, as the grid scrolls in.

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
      lead="It does not work online."
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
      Vow refuses to approve while any network is reachable. iPads take device management well, so a
      team can enforce that as policy.
    </Tile>
  );
}

function Station() {
  return (
    <Tile area="station" dark>
      <div className="vb-claim">
        <span className="vb-claim-lead">A signing station</span>
        <span className="vb-claim-text">Nothing else runs here.</span>
        <span className="vb-claim-note">
          A sandboxed, signed app on an iPad mini with one job. The attacks that live in browsers
          and their extensions have nowhere to land.
        </span>
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
      Raw transaction bytes or a <code>.vow</code> file in, an approval out. AirDrop and USB storage
      today; QR is planned.
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

function Explain() {
  const [picture, width] = usePictureWidth();
  return (
    <Tile
      area="explain"
      drift={72}
      lead="Explained on the device."
      picture={
        <div ref={picture} className="vb-picture" aria-hidden>
          {width > 0 && (
            <Stage<Beat>
              width={width}
              height={262}
              initial={before}
              poster={after}
              play="once"
              script={scripts[3]}
              className="vb-stage"
            >
              {(scene) => (
                <div className="vb-panel vb-request">
                  <div className="vb-request-head">
                    <span className="vb-name">Contributor grants</span>
                    <span className="vb-amount">12,500.00 USDC</span>
                  </div>
                  <Row title={<span className="vb-name vb-name--quiet">Treasury</span>} pad={14}>
                    <span className="vb-name">to Grants</span>
                  </Row>
                  <div className="vb-explain" data-on={on(scene.on)}>
                    <span>On-device explanation</span>
                    <p>
                      Sends 12,500 USDC from the team&rsquo;s Treasury vault to its Grants vault.
                    </p>
                  </div>
                </div>
              )}
            </Stage>
          )}
        </div>
      }
    >
      The app decodes the transaction, and Apple&rsquo;s on-device model puts it in plain words.
      There is no cloud fallback.
    </Tile>
  );
}

function Replay() {
  const [picture, width] = usePictureWidth();
  return (
    <Tile
      area="replay"
      drift={40}
      lead="Replayed before you sign."
      picture={
        <div ref={picture} className="vb-picture" aria-hidden>
          {width > 0 && (
            <Stage<Beat>
              width={width}
              height={206}
              initial={before}
              poster={after}
              play="once"
              script={scripts[4]}
              className="vb-stage"
            >
              {(scene) => (
                <div className="vb-panel">
                  <Row title={<span className="vb-name">Accounts in the file</span>} pad={14}>
                    <span className="vb-name vb-name--quiet">3</span>
                  </Row>
                  <Row title={<span className="vb-name">Replayed on this iPad</span>} pad={14}>
                    <Check on={scene.on} pending size={22} />
                  </Row>
                </div>
              )}
            </Stage>
          )}
        </div>
      }
    >
      A <code>.vow</code> file carries the accounts the transaction touches, so the iPad can run it
      offline and show what would change.
    </Tile>
  );
}

const EVIDENCE = ['This iPad', 'This security key', 'This member'];

function Evidence() {
  return (
    <Tile
      area="evidence"
      drift={72}
      lead="Evidence with every approval."
      picture={
        <span className="vb-chips">
          {EVIDENCE.map((label) => (
            <span key={label}>
              <Icon name="check" size={14} />
              {label}
            </span>
          ))}
        </span>
      }
    >
      Each approval records what made it. The design attaches that to the signature, to be checked
      on-chain.
    </Tile>
  );
}

/** The features grid: eight tiles of three sizes. */
export function Bento() {
  return (
    <div className="vb">
      <div className="vb-grid">
        <Offline />
        <Station />
        <Squads />
        <Explain />
        <File />
        <Team />
        <Replay />
        <Evidence />
      </div>
    </div>
  );
}
