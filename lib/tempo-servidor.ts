import "server-only";
import { diaEmSP } from "@/lib/tempo";

/**
 * O "hoje" do produto. Espelha `public.hoje_sp()` do banco: quem grava data
 * pelo app e quem grava por default do Postgres precisam concordar.
 */
export function hoje(): string {
  return diaEmSP(new Date());
}
