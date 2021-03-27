
ns main

main = proc()
	import floops
	import stdos
	import stdbytes

	ops-by-name = map(
		'files'
				proc()
					ok err out errout = call(stdos.exec 'ls'):
					outstr = if(ok call(stdbytes.string out) call(stdbytes.string errout))
					list(ok err outstr)
				end

		'makelist'
				proc(input)
					import stdfu
					list(true '' call(stdfu.filter split(input '\n') func(x) not(eq(x '')) end))
				end
	)

	operations = list(
		list('files')
		list('makelist')
	)

	call(floops.run-ops ops-by-name 'no-state' operations)
end

endns

