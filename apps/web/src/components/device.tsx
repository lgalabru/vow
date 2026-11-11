import { type ReactNode } from 'react';
import './device.css';

const on = (value: boolean) => (value ? '' : undefined);

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
