GLOBAL_LIST_EMPTY(allfaxes)
GLOBAL_LIST_EMPTY(alldepartments)
GLOBAL_LIST_EMPTY(adminfaxes) //cache for faxes that have been sent to admins

/obj/machinery/photocopier/faxmachine
	name = "fax machine"
	desc = "Sent papers and pictures far away! Or to your co-worker's office a few doors down."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "fax"
	insert_anim = "faxsend"
	var/send_access = list(list(access_lawyer, access_bridge, access_armory, access_qm, access_heads, access_cent_general))

	var/static/list/admin_departments = list("[GLOB.using_map.boss_name]", "SFV Stinger Command Departament", "Sol Governmental Authority", "Sol-Gov Job Boards", "Sol-Gov Supply Departament", "FTU Agency")


	idle_power_usage = 30
	active_power_usage = 200

	var/obj/item/card/id/scan = null // identification
	var/authenticated = 0
	var/sendcooldown = 0 // to avoid spamming fax messages
	var/department = "Unknown" // our department
	var/destination = null // the department we're sending to

/obj/machinery/photocopier/faxmachine/Initialize(mapload)
	. = ..()

	GLOB.allfaxes += src
	if(!destination) destination = "[GLOB.using_map.boss_name]"
	if( !(("[department]" in GLOB.alldepartments) || ("[department]" in admin_departments)) )
		GLOB.alldepartments |= department
	..()

/obj/machinery/photocopier/faxmachine/attack_hand(mob/user as mob)
	user.set_machine(src)

	ui_interact(user)

/**
 *  Display the NanoUI window for the fax machine.
 *
 *  See NanoUI documentation for details.
 */
/obj/machinery/photocopier/faxmachine/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	user.set_machine(src)

	var/list/data = list()
	if(scan)
		data["scanName"] = scan.name
	else
		data["scanName"] = null
	data["bossName"] = GLOB.using_map.boss_name
	data["authenticated"] = authenticated
	data["copyItem"] = copyitem
	if(copyitem)
		data["copyItemName"] = copyitem.name
	else
		data["copyItemName"] = null
	data["cooldown"] = sendcooldown
	data["destination"] = destination

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "fax.tmpl", src.name, 500, 500)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(10) //this machine is so unimportant let's not have it update that often.

/obj/machinery/photocopier/faxmachine/Topic(href, href_list)
	if(href_list["send"])
		if(copyitem)
			if (destination in admin_departments)
				send_admin_fax(usr, destination)
			else
				sendfax(destination)

			if (sendcooldown)
				spawn(sendcooldown) // cooldown time
					sendcooldown = 0

	else if(href_list["remove"])
		if(copyitem)
			if(get_dist(usr, src) >= 2)
				to_chat(usr, "\The [copyitem] is too far away for you to remove it.")
				return
			copyitem.loc = usr.loc
			usr.put_in_hands(copyitem)
			to_chat(usr, "<span class='notice'>You take \the [copyitem] out of \the [src].</span>")
			copyitem = null

	if(href_list["scan"])
		if (scan)
			if(ishuman(usr))
				scan.loc = usr.loc
				if(!usr.get_active_hand())
					usr.put_in_hands(scan)
				scan = null
			else
				scan.loc = src.loc
				scan = null
		else
			var/obj/item/I = usr.get_active_hand()
			if (istype(I, /obj/item/card/id) && usr.unEquip(I))
				I.loc = src
				scan = I
		authenticated = 0

	if(href_list["dept"])
		var/lastdestination = destination
		destination = input(usr, "Which department?", "Choose a department", "") as null|anything in (GLOB.alldepartments + admin_departments)
		if(!destination) destination = lastdestination

	if(href_list["auth"])
		if ( (!( authenticated ) && (scan)) )
			if (has_access(send_access, scan.GetAccess()))
				authenticated = 1

	if(href_list["logout"])
		authenticated = 0

	SSnano.update_uis(src)

/obj/machinery/photocopier/faxmachine/attackby(obj/item/O as obj, mob/user as mob)
	if(istype(O, /obj/item/paper) || istype(O, /obj/item/photo) || istype(O, /obj/item/paper_bundle))
		if(!copyitem)
			user.drop_item()
			copyitem = O
			O.loc = src
			to_chat(user, "<span class='notice'>You insert \the [O] into \the [src].</span>")
			playsound(loc, "sound/machines/click.ogg", 100, 1)
			flick(insert_anim, src)
		else
			to_chat(user, "<span class='notice'>There is already something in \the [src].</span>")
	else if(istype(O, /obj/item/device/multitool) && panel_open)
		var/input = sanitize(input(usr, "What Department ID would you like to give this fax machine?", "Multitool-Fax Machine Interface", department))
		if(!input)
			to_chat(usr, "No input found. Please hang up and try your call again.")
			return
		department = input
		if( !(("[department]" in GLOB.alldepartments) || ("[department]" in admin_departments)) && !(department == "Unknown"))
			GLOB.alldepartments |= department
	else if(isWrench(O))
		//playsound(loc, O.usesound, 50, 1)
		anchored = !anchored
		to_chat(user, "<span class='notice'>You [anchored ? "wrench" : "unwrench"] \the [src].</span>")
/*
	else if(default_deconstruction_screwdriver(user, O))
		return
	else if(default_deconstruction_crowbar(user, O))
		return
*/
	return

/obj/machinery/photocopier/faxmachine/proc/sendfax(var/destination)
	if(stat & (BROKEN|NOPOWER))
		return

	use_power_oneoff(200)

	var/success = 0
	for(var/obj/machinery/photocopier/faxmachine/F in GLOB.allfaxes)
		if( F.department == destination )
			success = F.receivefax(copyitem)

	if (success)
		visible_message("[src] beeps, \"Message transmitted successfully.\"")
		//sendcooldown = 600
	else
		visible_message("[src] beeps, \"Error transmitting message.\"")

/obj/machinery/photocopier/faxmachine/proc/receivefax(var/obj/item/incoming)
	if(stat & (BROKEN|NOPOWER))
		return 0

	if(department == "Unknown")
		return 0	//You can't send faxes to "Unknown"

	flick("faxreceive", src)
	playsound(loc, "sound/machines/printer.ogg", 50, 1)


	// give the sprite some time to flick
	sleep(20)

	if (istype(incoming, /obj/item/paper))
		copy(incoming)
	else if (istype(incoming, /obj/item/photo))
		photocopy(incoming)
	else if (istype(incoming, /obj/item/paper_bundle))
		bundlecopy(incoming)
	else
		return 0

	use_power_oneoff(active_power_usage)
	return 1

/obj/machinery/photocopier/faxmachine/proc/send_admin_fax(var/mob/sender, var/destination)
	if(stat & (BROKEN|NOPOWER))
		return

	use_power_oneoff(200)

	//received copies should not use toner since it's being used by admins only.
	var/obj/item/rcvdcopy
	if (istype(copyitem, /obj/item/paper))
		rcvdcopy = copy(copyitem, 0)
	else if (istype(copyitem, /obj/item/photo))
		rcvdcopy = photocopy(copyitem, 0)
	else if (istype(copyitem, /obj/item/paper_bundle))
		rcvdcopy = bundlecopy(copyitem, 0)
	else
		visible_message("[src] beeps, \"Error transmitting message.\"")
		return

	rcvdcopy.loc = null //hopefully this shouldn't cause trouble
	GLOB.adminfaxes += rcvdcopy

	//message badmins that a fax has arrived
	if (destination == GLOB.using_map.boss_name)
		message_admins(sender, "[uppertext(GLOB.using_map.boss_short)] FAX", rcvdcopy, "CentComFaxReply", "#006100")
	else if (destination == "Sol Governmental Authority") // Vorestation Edit
		message_admins(sender, "SOL GOVERNMENTAL FAX ", rcvdcopy, "SolGovFaxReply", "#1f66a0")
	else if (destination == "Sol-Gov Supply Departament")
		message_admins(sender, "[uppertext(GLOB.using_map.boss_short)] SUPPLY FAX", rcvdcopy, "SolGovFaxReply", "#5f4519")
	else if (destination == "FTU Agency")
		message_admins(sender, "FTU AGENCY FAX", rcvdcopy, "FtuFaxReply", "#3ec4ad")
	else
		message_admins(sender, "[uppertext(destination)] FAX", rcvdcopy, "UNKNOWN")


	sendcooldown = 1800
	sleep(50)
	visible_message("[src] beeps, \"Message transmitted successfully.\"")

// Turns objects into just text.
/obj/machinery/photocopier/faxmachine/proc/make_summary(obj/item/sent)
	if(istype(sent, /obj/item/paper))
		var/obj/item/paper/P = sent
		return P.info
	if(istype(sent, /obj/item/paper_bundle))
		. = ""
		var/obj/item/paper_bundle/B = sent
		for(var/i in 1 to B.pages.len)
			var/obj/item/paper/P = B.pages[i]
			if(istype(P)) // Photos can show up here too.
				if(.) // Space out different pages.
					. += "<br>"
				. += "PAGE [i] - [P.name]<br>"
				. += P.info


/obj/machinery/photocopier/faxmachine/proc/message_admins(var/mob/sender, var/faxname, var/obj/item/sent, var/reply_type, font_colour="#006100")
	var/msg = "<span class='notice'><b><font color='[font_colour]'>[faxname]: </font>[get_options_bar(sender, 2,1,1)]"
	msg += "(<a href='?_src_=holder;FaxReply=\ref[sender];originfax=\ref[src];replyorigin=[reply_type]'>REPLY</a>)</b>: "
	msg += "Receiving '[sent.name]' via secure connection ... <a href='?_src_=holder;AdminFaxView=\ref[sent]'>view message</a></span>"

	GLOB.fax_cache += "*[time_stamp()]*: DESTINATION - [msg]<br>"

	for(var/client/C in GLOB.admins)
		if(check_rights((R_ADMIN|R_MOD),0,C))
			to_chat(C,msg)
			C << 'sound/machines/printer.ogg'

	// Webhooks don't parse the HTML on the paper, so we gotta strip them out so it's still readable.
	var/summary = make_summary(sent)
	summary = paper_html_to_plaintext(summary)

	log_game("Fax to [lowertext(faxname)] was sent by [key_name(sender)].")
	log_game(summary)

	var/webhook_length_limit = 1900 // The actual limit is a little higher.
	if(length(summary) > webhook_length_limit)
		summary = copytext(summary, 1, webhook_length_limit + 1)
		summary += "\n\[Закончилось место в факсе\]"

	SSwebhooks.send(
		WEBHOOK_FAX_SENT,
		list(
			"name" = "[faxname] '[sent.name]' sent from [key_name(sender)]",
			"body" = summary
		)
	)
