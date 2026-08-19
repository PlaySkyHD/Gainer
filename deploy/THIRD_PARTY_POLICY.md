# Third-party dependency policy

The MVP accepts the permissive MIT, ISC, BSD, Apache-2.0, 0BSD, BlueOak, CC0, CC-BY, MPL-2.0, Python-2.0, and PostgreSQL license families represented in the committed lockfiles. npm packages containing LGPL metadata are `sharp`/`libvips` platform build dependencies; the application uses Next.js static export with unoptimized images and does not ship those native libraries in the final Caddy image. Their notices remain in the locked dependency tree and image build layers.

CI rejects packages with missing or newly introduced license expressions until this file and the explicit allowlists are reviewed. It also fails on RAG/pgvector dependencies and unapproved exercise media. Automated CVE scanning of dependencies and container images is intentionally not a release gate for this private MVP; dependency versions remain locked and updates are reviewed separately.
