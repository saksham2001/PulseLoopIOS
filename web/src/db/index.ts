import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error(
    "DATABASE_URL is not set. Provision Neon (vercel integration add neon) and run `vercel env pull .env.local`.",
  );
}

const sql = neon(connectionString);
export const db = drizzle(sql, { schema });
export { schema };
