(**************************************************************************)
(*  SX client                                                             *)
(*  Copyright (C) 2012-2015 Skylable Ltd. <info-copyright@skylable.com>   *)
(*                                                                        *)
(*  This library is free software; you can redistribute it and/or         *)
(*  modify it under the terms of the GNU Lesser General Public            *)
(*  License as published by the Free Software Foundation; either          *)
(*  version 2.1 of the License, or (at your option) any later version.    *)
(*                                                                        *)
(*  This library is distributed in the hope that it will be useful,       *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *)
(*  Lesser General Public License for more details.                       *)
(*                                                                        *)
(*  You should have received a copy of the GNU Lesser General Public      *)
(*  License along with this library; if not, write to the Free Software   *)
(*  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,            *)
(*  MA  02110-1301  USA                                                   *)
(*                                                                        *)
(*  As a special exception to the GNU Library General Public License,     *)
(*  you may link, statically or dynamically, a "work that uses the        *)
(*  Library" with a publicly distributed version of the Library to        *)
(*  produce an executable file containing portions of the Library, and    *)
(*  distribute that executable file under terms of your choice, without   *)
(*  any of the additional requirements listed in clause 6 of the GNU      *)
(*  Library General Public License. By "a publicly distributed version    *)
(*  of the Library", we mean either the unmodified Library, or a          *)
(*  modified version of the Library that is distributed under the         *)
(*  conditions defined in clause 3 of the GNU Library General Public      *)
(*  License. This exception does not however invalidate any other         *)
(*  reasons why the executable file might be covered by the GNU Library   *)
(*  General Public License.                                               *)
(**************************************************************************)

open Lwt
type log_id = {
  id: int;
  nesting: string;
  start: float;
}

let log_id_key = Lwt.new_key ()
let id = ref 0

let section = Lwt_log.Section.make "request"

let rec lines_of_string str pos lst =
  try
    let next_pos = String.index_from str pos '\n' in
    lines_of_string str (next_pos+1) (String.sub str pos (next_pos - pos) :: lst)
  with Not_found -> List.rev (String.sub str pos (String.length str - pos) :: lst)

let log_nested ?exn level log_id t sep message =
  let dt_ms = (t -. log_id.start) *. 1000. in
  let prefix = Printf.sprintf "[%6d][+%7.3f ms]" log_id.id dt_ms in
  let linesep = ("\n" ^ (String.make (String.length prefix) ' ') ^ log_id.nesting ^ "│") in
  let msg = String.concat linesep (lines_of_string message 0 []) in
  Lwt_log.ign_log_f ?exn ~section ~level "%s%s%s%s" prefix log_id.nesting sep msg

let log level ?exn f =
  if Lwt_log.Section.level section <= level then
    let msg = f () in
    match Lwt.get log_id_key with
    | Some log_id ->
      let t = Unix.gettimeofday () in
      log_nested ?exn level log_id t "├" msg
    | None ->
      Lwt_log.ign_log_f ?exn ~section ~level "[     -]             │%s" msg

let with_label label f =
  if Lwt_log.Section.level section > Lwt_log.Info then f ()
  else
    let prev_log_id = match Lwt.get log_id_key with
      | None -> incr id; { id = !id; nesting = ""; start = Unix.gettimeofday () }
      | Some log_id -> log_id in
    let t0 = Unix.gettimeofday () in
    log_nested Lwt_log.Info prev_log_id t0 "├╮" label;
    let log_id = { prev_log_id with nesting = prev_log_id.nesting ^ "│" } in
    Lwt.with_value log_id_key (Some log_id) f >>= fun r ->
    let t = Unix.gettimeofday () in
    log_nested Lwt_log.Info prev_log_id t "├┘" (Printf.sprintf "<+%7.3f> ms" ((t -. t0) *. 1000.));
    return r

let debug ?exn f = log Lwt_log.Debug ?exn f
let info ?exn f = log Lwt_log.Info ?exn f

let notice ?exn f = Lwt_log.ign_notice_f ?exn f
let warning ?exn f = Lwt_log.ign_warning_f ?exn f
let error ?exn f = Lwt_log.ign_error_f ?exn f
