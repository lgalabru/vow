import { FactorsSite } from '../components/factors';

/**
 * The repository's star count, read on the server at most once an hour so the
 * page itself makes no third-party request. Null while the repository is
 * private or GitHub cannot be reached.
 */
async function repositoryStars(): Promise<number | null> {
  try {
    const response = await fetch('https://api.github.com/repos/lgalabru/vow', {
      headers: { Accept: 'application/vnd.github+json' },
      next: { revalidate: 3600 },
    });
    if (!response.ok) return null;
    const body: unknown = await response.json();
    const count = (body as { stargazers_count?: unknown }).stargazers_count;
    return typeof count === 'number' ? count : null;
  } catch {
    return null;
  }
}

/** Vow's public landing page. */
export default async function Page() {
  return <FactorsSite stars={await repositoryStars()} />;
}
