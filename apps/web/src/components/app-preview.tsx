'use client';

import { Tabs } from '@base-ui/react/tabs';
import {
  ArrowUpRight,
  BadgeCheck,
  Check,
  ChevronLeft,
  CircleCheck,
  FileCheck2,
  Fingerprint,
  Folder,
  KeyRound,
  LockKeyhole,
  PenLine,
  Share,
  WifiOff,
} from 'lucide-react';

type Stage = 'review' | 'authorize' | 'export';

const stages = [
  { value: 'review', label: 'Review', detail: 'Understand the request.' },
  { value: 'authorize', label: 'Authorize', detail: 'Make your approval explicit.' },
  { value: 'export', label: 'Export', detail: 'Bring your approval back to the team.' },
] as const;

function DeviceScreen({ stage }: { readonly stage: Stage }) {
  const active = stages.findIndex((item) => item.value === stage);
  return (
    <div className="ipad" aria-hidden="true">
      <span className="ipad-camera" />
      <div className="ipad-screen">
        <div className="app-status">
          <span>
            9:41 <b>Vow</b>
          </span>
          <span>100% ▰</span>
        </div>
        <div className="app-title">
          <span>Cancel</span>
          <b>Request approval</b>
          <LockKeyhole />
        </div>
        <div className="app-progress">
          {stages.map((item, index) => (
            <div key={item.value} className={index <= active ? 'complete' : ''}>
              <span>{index < active ? <Check /> : index + 1}</span>
              <b>{item.label}</b>
            </div>
          ))}
        </div>
        <div className="app-content">
          <div className="app-breadcrumb">
            <Folder /> Example team <span>/</span> Treasury <span>/</span> <b>Devnet</b>
          </div>
          {stage === 'review' && (
            <div className="review-layout">
              <div>
                <p className="app-eyebrow">TRANSACTION REQUEST</p>
                <h3>Contributor grants</h3>
                <p className="app-amount">
                  12,500.00 <span>USDC</span>
                </p>
                <p className="app-description">Review the details before you approve.</p>
              </div>
              <div className="app-detail-card">
                <div>
                  <span>Destination</span>
                  <b>
                    Community grants <ArrowUpRight />
                  </b>
                </div>
                <div>
                  <span>Network</span>
                  <b>Solana Devnet</b>
                </div>
                <div>
                  <span>Approval policy</span>
                  <b>2 of 3 members</b>
                </div>
                <div>
                  <span>Transaction checks</span>
                  <b className="app-success">
                    <CircleCheck /> Passed
                  </b>
                </div>
              </div>
            </div>
          )}
          {stage === 'authorize' && (
            <div className="authorize-layout">
              <div className="request-summary">
                <p className="app-eyebrow">YOUR APPROVAL</p>
                <h3>Contributor grants</h3>
                <p className="app-amount">
                  12,500.00 <span>USDC</span>
                </p>
                <dl>
                  <div>
                    <dt>Destination</dt>
                    <dd>Community grants</dd>
                  </div>
                  <div>
                    <dt>Approval policy</dt>
                    <dd>
                      Treasury quorum <small>2 of 3 members</small>
                    </dd>
                  </div>
                </dl>
                <div className="app-digest">
                  <LockKeyhole /> Bound to this request
                </div>
              </div>
              <div className="consent-panel">
                <b>Your consent</b>
                <div className="signature-paper">
                  <svg viewBox="0 0 420 140" fill="none">
                    <path
                      d="M55 105c25-10 66-83 51-85-18-2-30 102-13 105 19 3 43-77 31-74-9 2-4 69 11 63 14-5 21-50 22-38 2 39 8 36 21 18 10-14 16-24 17-15 2 18 9 18 20 3 15-18 10-9 17 4 7 12 23-12 28-13 13-2-7 25 8 22 19-3 39-18 43-23M64 126c77-9 174-16 263-15"
                      stroke="currentColor"
                      strokeWidth="2.6"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                  <span>Handwritten consent</span>
                </div>
                <div className="app-requirements">
                  <span>
                    <PenLine /> Consent
                  </span>
                  <span>
                    <KeyRound /> Security key
                  </span>
                  <span>
                    <Fingerprint /> This iPad
                  </span>
                </div>
              </div>
            </div>
          )}
          {stage === 'export' && (
            <div className="export-layout">
              <BadgeCheck />
              <h3>Approval created.</h3>
              <p>Ready to share with your team.</p>
              <div className="export-file">
                <FileCheck2 />
                <div>
                  <b>Contributor grants</b>
                  <span>Signed approval · Sample</span>
                </div>
                <Share />
              </div>
              <small>The approval stays bound to the request you reviewed.</small>
            </div>
          )}
        </div>
        <div className="app-actions">
          <span>
            <ChevronLeft /> Back
          </span>
          <span className="app-primary">
            {stage === 'review' ? (
              'Continue'
            ) : stage === 'authorize' ? (
              'Authorize'
            ) : (
              <>
                <Share /> Share approval
              </>
            )}
          </span>
        </div>
        <div className="app-footer">
          <span>
            <WifiOff /> Offline
          </span>
          <span>
            Sample request <span>·</span> 04:58
          </span>
        </div>
        <div className="home-indicator" />
      </div>
    </div>
  );
}

/** A local, non-signing walkthrough. It never requests a wallet or device credential. */
export function AppPreview() {
  return (
    <Tabs.Root defaultValue="authorize" className="preview" id="experience">
      <div className="preview-panels">
        {stages.map((stage) => (
          <Tabs.Panel
            key={stage.value}
            value={stage.value}
            aria-label={`${stage.label} app preview`}
          >
            <DeviceScreen stage={stage.value} />
          </Tabs.Panel>
        ))}
      </div>
      <Tabs.List activateOnFocus className="preview-tabs" aria-label="Explore the approval flow">
        {stages.map((stage, index) => (
          <Tabs.Tab key={stage.value} value={stage.value}>
            <span>{index + 1}</span>
            {stage.label}
          </Tabs.Tab>
        ))}
      </Tabs.List>
      {stages.map((stage) => (
        <Tabs.Panel key={stage.value} value={stage.value} className="preview-caption">
          <p>{stage.detail}</p>
        </Tabs.Panel>
      ))}
      <p className="preview-note">
        Interactive preview with sample data. No signing keys are used.
      </p>
    </Tabs.Root>
  );
}
