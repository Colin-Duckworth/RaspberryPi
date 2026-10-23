## Notes Document
Purpose: The reasoning here is to just explain the concepts of what I learned to understand the internet and networking in general more deeply.

1. What is a DNS / DNS Server and what role does it serve?
	DNS stands for Domain Name System, it is a tool that abstracts IP addresses under domain names. For instance, when I want to go
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
		   
4. What is a port on the Pi (or a computer in general)?
	A port is not a physical hole in the case or place to plug in a cable, it is a 16 bit identifier included in incoming packets that tells the linux kernel where to
	direct incoming data. All it is is a tool to identify application destination on a device for data. Ports are bidirectional, when the laptop connects to the pi, 
	the laptop chooses a random port, and the pi has a designated port (8080 in this case).
	
	Two Things naturally result from this:
		1. Two applications cannot have the same port
		2. Most ports sit empty
		
	A server's port needs to be predictable. Many applications have default ports that we never even have to handle, SSH runs on port 22, websites use port 80 for 
	HTTP (standard) or 443 for HTTPS (encrypted) traffic. You can use the ss linux command to see socket information (what's listening where). For instance when 
	you type in the IP of  a websites, your browser actually adds the :80 port out of convention. Ports under 1024 are reserved for well known services so only the 
	root can claim them. Most of the port numbers are selected out of convention.
	
	Programs runing on the pi actually occupy multiple ports. For instance,
		1. Pi Hole does the work on port 53, and administration happens on port 8080
		2. Qbittorent does work on port 24950, 8081
		
5. Wtf is a firewall? and what's ufw?
	A firewall is simply a tool used to police traffic coming into a device. In it's simplest form, it evaluates three pieces of information to determine what
	to do with the incoming data.
		1. Where is this data coming from: IP address and port?
		2. Where is this data heading to: IP address and port?
		3. What connection type does this data want to establish: TCP UDP?
	
	Once the firewall has that infomation it can do three Things
		1. Accept the packet (forwards the packet into the desired destination)
		2. Drop the packet (basically ignore it)
		3. Reject the packet (returns a no to sender)
		
	UFW stands for uncomplicated firewall, it is the standard firewall package on unbuntu devices.
	
6. Ponder putting this all together.
	Now we have seen how all of these systems interact together so now we can consider the practical development of some tool. I do RF, so let's say for the sake
	of argument, that I want to create a web accessible platform that monitors the RF spectrum in my house that's accessible from anywhere. Well a hardware toolchain
	for something like that could be straightforward. 
		
		SDR -> Raspberry Pi -> router
		
	Now if we consider the software toolchain for such a project it could be achieved by setting the SDR to write it's data to a directory on the PI regularly during
	operation. Then a simple application could be developed that uses a .py or .sh script to analyze the data written by the SDR and update the HTML setup with nginx.
	Now this website that displays the spectrum information would be reachable using the nginx port on the PI. This is what it could look like over LAN, to make it
	accessible anywhere, you'd need to to create a tunnel to the gateway and register the site in DNS.
	
7. What is a VPN?
	VPN stands for Virtual Private Network, simply put, it creates a secure tunnel between your device and the VPN server and uses the server as an intermediatry to 
	access the broader internet. So in practice, a correctly configured VPN causes the device to only communicate directly through an encrypted tunenel with the VPN 
	server. Without a VPN, your ISP can see what IP addresses you communicate with, and often DNS queries too, generally not actual content though. With a VPN, your 
	ISP only sees you communicate with a VPN server. Data being exchanged with the vpn server is encrypted, DNS queries are handled within the VPN server so your 
	privacy is much more optimized.
	Technically, a VPN actually contains two parts. The service and the client program. The service is what you pay for, VPN servers around the world to tunnel to.
	The client program is what connects to one of those servers and sets up the secure tunnel. The client programs are highly standardized and free to download, The
	most common are OpenVPN and WireGuard.
	
	*NOTE: For this to work properly and avoid leaks, the device needs to use the VPN server's DNS, not the ISP's DNS*