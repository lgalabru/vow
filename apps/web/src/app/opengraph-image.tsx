import { ImageResponse } from 'next/og';

export const alt = 'Vow — Shared control. Personal approval. Built for iPad and Mac.';
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
        background: '#fafaf9',
        color: '#1d1d1f',
        fontFamily: 'sans-serif',
      }}
    >
      <div style={{ display: 'flex', fontSize: 34, fontWeight: 600, color: '#0066cc' }}>vow</div>
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
        <span>Shared control.</span>
        <span style={{ color: '#75757a' }}>Personal approval.</span>
      </div>
      <div style={{ display: 'flex', marginTop: 'auto', fontSize: 22, color: '#6e6e73' }}>
        Built for iPad. Designed to stay offline.
      </div>
    </div>,
    size,
  );
}
