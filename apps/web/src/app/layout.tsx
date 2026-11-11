import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL('https://vow.scarce.sh'),
  title: 'Vow — Shared control. Personal approval.',
  description:
    'An offline approval app for iPad, with a ceremony companion for Mac. Review clearly, authorize deliberately, and keep your team’s signing keys close.',
  openGraph: {
    title: 'Vow — Shared control. Personal approval.',
    description:
      'A dedicated place for your team’s approvals. Built for iPad. Designed to stay offline.',
    url: 'https://vow.scarce.sh',
    siteName: 'Vow',
    type: 'website',
  },
  twitter: { card: 'summary_large_image' },
};

export const viewport: Viewport = { themeColor: '#ffffff' };

/** The public site uses local system fonts and makes no third-party requests. */
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
