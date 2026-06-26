CREATE TABLE "coach_sessions" (
	"response_id" text PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"messages" text NOT NULL,
	"pending_tool_calls" text DEFAULT '[]' NOT NULL,
	"injected_json" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "coach_sessions" ADD CONSTRAINT "coach_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "coach_sessions_user_idx" ON "coach_sessions" USING btree ("user_id");