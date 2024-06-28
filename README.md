_This information is being posted for historical record / information sake only in case it comes in handy for a future developer who needs something similar for a project._

# Progress Update

The initial intent of PublicNexus was to fill a perceived need by the general community and basic developers however on further discussions and examining the publicly available
RPCs on the XDC Network, it has become apparent that this need has already been filled by Ankr (and so PublicNexus isn't really required).

This is based on the following as of today (29/06/2024):
- The Ankr site offers public RPC access allowing up to 20requests/sec. This is more than the average community member and basic developer would need for general transactions via their Web3 wallet.
- If actually signing up for their "Freemium" service then this rate limit is increased to 30requests/min. This is also more than the average community member and basic developer would need for general transactions via their Web3 wallet.
- Their Premium service offers a rate limit of 1500requests/sec at a cost (at present for Node API) of USD$0.02/1000requests.

Let's assume that an XDC node providing an RPC is running on a VPS costing $100/month (arbitrary figure plucked out of the air; there are better more expensive VPSs available and similarly the XDC client can also run on cheaper VPSs
if expecting less load).

_$100/month = 5M requests/month via Ankr._

The generous limit shown above means that developers working with an active commercial product may be better off using the Ankr paid service.

A load balancer covering all public RPC's doesn't seem to be required.

As one developer from a prominent project on the network indicated regarding how they operate:
- Their project runs its own Archive node (as others don't need it)
- For all Full node RPC requests they send them to Ankr

For general community and basic developers, it seems that the best option is Ankr as a first point of contact.

As mentioned above, the content in this repo is provided more as a record in case of future need.

We were in the process of actively onboarding a new team member to manage enterprise RPC deployments (currently employed as a senior solutions architect by a large US multinational tech provider and
who's day-to-day job at present involves enterprise deployments with Cloudflare, Kubernetes, load balancers, redundant ingress etc and who's clients include the largest bank in our country, several 
government departments and multi-billion dollar corporates in Asia Pacific. Even better is that he's already familiar with the XDC ecosystem ;)

We will have further discussions with other developers in the ecosystem before making a final decision on what to do with our actively running servers, however it is looking very much like we will discontinue the service and pause
further development as it isn't really required to add ourselves as another service provider in the space.
