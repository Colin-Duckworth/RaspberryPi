## Notes Document
Purpose: The reasoning here is to just explain the concepts of what I learned to understand the internet and networking in general more deeply.

1. What is a DNS / DNS Server and what role does it serve?
		DNS stands for Domain Name System, it is a tool that abstracts IP addresses under more readable URLs. For instance, when I want to go
	to youtube to watch ASMR slime videos, and I type in youtube.com, the DNS converts that link "youtube.com" to an IP address which is just a 
	sequence of numbers like 142.250.x.xxx that allows routers to forward packets. A DNS Server is the actual location where that DNS tool lives,
	in the case of the Pi-Hole, we are manipulating the ability to define a DNS server's lookup tables to block advertisements
		
2. How does a Pi Hole work?
		A pi hole works by making a custom DNS server that intentionally returns null IP addresses for websites that distribute ads to users. This works
	because the majority of ads you see on the internet come from a different domain than the content you want to access. Meaning when you load a 
	website that has advertisements, call it stuff.com. Stuff.com's content you want to read resolves to some IP address, and it also loads content from
	a separate domain, call it ads.com. Now there are various implementations here of custom DNS configuration, so some nuance is required.
		Approach 1
			On the device side, you can choose a custom IP address to set as your DNS, meaning when you want content from some domain, it goes to that IP
			address to convert a domain to an IP address.
		Approach 2	
			On the router side, because it is the LAN gateway, you can set the Pi as the default DNS so all DNS requests in the network from devices are
			forwarded to the router, which are then filtered through the pi hole where the domain is compared with the blacklist.
				The router can also do this by handing out the Pi's IP address as the DNS to every device through DHCP (see 3).
			
		In either case, the result is the following: The DNS of the pi hole is prompted to resolve a domain, and if it's on the blacklist, it returns a null
	IP address, and if it isn't it returns the actual IP address. So the ads on the site don't load but the content does. This is an imperfect tool however, 
	it relies on A. The content you want to view comes from a different domain than the advertisements, and B. that the domain the ads are coming from is on the
	pi hole's blacklist.
		
3. What is DHCP?
	Dynamic Host Configuration Protocol (DHCP) is a tool that automatically leases IP addresses to devices on a network, and also tells them the DNS IP address and
	the default gateway IP address. The default gateway IP address is important because it establishes the first jump that devices on a network make when
	communicating to other devices outside of your subnet.
	
	Consider the sequence:
		1. I go to someone's house and log in to their wifi
		2. DHCP automatically assigns my device an IP address and tells my device the IP address of the DNS and the default gateway
		3. I search google.com on my device
		4. My device uses the DHCP provided DNS IP address to resolve google.com to an IP address for my device to communicate with and sends to the DHCP designated
		   gateway IP address.