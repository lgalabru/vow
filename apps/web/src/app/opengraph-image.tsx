import { ImageResponse } from 'next/og';

export const alt = 'Vow — 3-factor authentication for multisig approvals, offline on iPad.';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

/** Static social card with no remote font or image dependencies. */
export default function OpenGraphImage() {
  return new ImageResponse(
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        padding: '65px 80px',
        background: '#ffffff',
        color: '#0b0b0c',
        fontFamily: 'sans-serif',
      }}
    >
      <div style={{ display: 'flex', fontSize: 34, fontWeight: 600, color: '#0b0b0c' }}>vow</div>
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          marginTop: 90,
          fontSize: 76,
          lineHeight: 1.1,
          fontWeight: 600,
        }}
      >
        <span>3-Factor</span>
        <span style={{ color: '#a1a1a6' }}>Authentication.</span>
      </div>
      <div style={{ display: 'flex', marginTop: 'auto', fontSize: 22, color: '#6e6e73' }}>
        Signature, security key and Touch ID. Offline, on iPad.
      </div>
    </div>,
    size,
  );
}
