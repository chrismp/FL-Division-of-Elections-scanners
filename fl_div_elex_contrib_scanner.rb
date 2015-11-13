[
	'rubygems',
	'mechanize',
	'sequel'
].each{|g|
	require g
}

fl_doeDB = Sequel.connect( 
	:adapter => 'mysql',
	:user=>ARGV[0], 
	:password=>ARGV[1], 
	:host=>ARGV[2],
	:database=>ARGV[3]
)

fl_doeDB.create_table? :fl_cmpgn_contrib do
#	primary_key :id
	Integer :elex_val, :null => false
	String :election_value, :null => false
	String :election_text, :null => false
	String :candidate
	String :candidate_party
	String :candidate_office
	String :committee
	String :committee_type
	Date :date
	Float :amount
	String :typ
	String :contributor_name
	String :address
	String :po_box
	String :city_state_zip
	String :address_clean
	String :city_state_zip_clean
	String :city
	String :state
	String :zip
	String :occupation
	String :inkind_description
#	index [:elex_val, :zip]
	index [:elex_value, :zip, :candidate, :committee]
end
cmpgn_contrib = fl_doeDB[:fl_cmpgn_contrib]


## Below code in MySQL should significant speed improvements. sequel gem does not appear to allow partitioning.

# alter table fl_cmpgn_contrib partition by range (elex_val) (
	# partition p1998 values less than (19990000),
	# partition p1996 values less than (19970000),
	# partition p2000 values less than (20010000),
	# partition p2002 values less than (20030000),
	# partition p2004 values less than (20050000),
	# partition p2006 values less than (20070000),
	# partition p2008 values less than (20090000),
	# partition p2010 values less than (20110000),
	# partition p2012 values less than (20130000),
	# partition p2014 values less than (20150000),
	# partition p2016 values less than (20170000),
	# partition p2018 values less than (20190000),
	# partition p2020 values less than (20210000),
	# partition p2022 values less than (20230000),
	# partition p2024 values less than (20250000),
	# partition premainder values less than (2147483647)
# );



fl_doe_url = 'http://election.dos.state.fl.us/campaign-finance/contrib.asp'

p "OPENING FORM URL TO SEARCH CONTRIBUTIONS..."
agent = Mechanize.new

begin
	page = agent.get(fl_doe_url)
rescue Exception => e
	p "ERROR: #{e}"
	p "RETRYING IN 30 SECONDS"
	sleep 30
	retry
end

election_option_arr = page.search('select[name="election"] option').map{|option| option['value']}[1..-1] # The value 'All' is located at index 0, so we exclude that one from the scan
election_name_arr = page.search('select[name="election"] option').map{|option| option.text}[1..-1]

election_option_arr.zip(election_name_arr){|election_value, election_text|
	if(election_value.include? 'GEN')
		['CanLName', 'ComName'].each{|record_type|
			[*('a'..'z'),*('0'..'9')].each{|letter_number|
			begin
				page = agent.get(fl_doe_url)
			rescue Exception => e
				p "ERROR: #{e}"
				p "RETRYING IN 30 SECONDS"
				sleep 30
				retry
			end

#form changed; this no longer works				doe_form = page.forms[1] # The form, in Mechanize object format
				doe_form = page.forms[0] # The form, in Mechanize object format
				
				doe_form[record_type] = letter_number  # This goes in the candidate "Last name" field. By default, "With candidate last name starts with" is checked off, so we search all candidates whose last name begins with this letter
				doe_form['election'] = election_value # Search all elections in the DOE campaign finance database
				doe_form['csort1'] = 'DAT' # Sort by earliest to latest contributions.
				doe_form['rowlimit'] = '' # NO LIMIT on how many records the query returns
				doe_form.radiobuttons[15].check # Check off the button for downloading DOE results in tab-delimited file

				if(record_type==='CanLName')
					doe_form.radiobuttons[5].check # Makes sure we click the "Search for a list of contributions" button, so we see each contribution to each candidate
				else
					doe_form.radiobuttons[10].check # Same as above, but for committees
				end
				

				p record_type
				p doe_form
				p "SUBMITTING FORM..."
				begin
					result = doe_form.submit.body
				rescue Exception => e
					p "ERROR: #{e}"
					p "RETRYING IN 30 SECONDS"
					sleep 30
					retry
				end
				
				
				p "QUERY COMPLETE! REMOVING RETURN CHARACTERS FROM BEGINNING AND END OF EACH RECORD..."
				results_arr = result.split("\n")

				p "DONE CLEANING RECORDS! ADDING CONTRIBUTIONS TO DATA TABLE..."
				previously_processed_row_arr = nil
				results_count = (1..results_arr.length-1).count

				col = record_type==='CanLName' ? 'candidate' : 'committee'
				tbl_data_count = cmpgn_contrib.where("election_value = '#{election_value}' AND #{col} LIKE '#{letter_number}%'").count

				if(results_count<tbl_data_count)
					next
				elsif(results_count===tbl_data_count)
					p "UP TO DATE FOR #{election_value} WHERE #{col} BEGINS WITH #{letter_number}"
				else 
					p "DELETING DUPLICATE RECORDS..."
					cmpgn_contrib.where("election_value = '#{election_value}' AND #{col} LIKE '#{letter_number}%'").delete
					(1..results_arr.length-1).each{|row_num|
						# p previously_processed_row_arr
						row_arr = results_arr[row_num].gsub("\r","").split("\t") # Array of current row
						row_length = row_arr.length

						begin
							row_arr2 = results_arr[row_num+1].gsub("\r","").split("\t") # Array of next row
							row2_length = row_arr2.length

							# If `row_length` is less than 5, it usually means the row got split in two, with the second half being the next row.
							# This `if` statement is for combining split rows into one
							if(row_length<=5)
								if(row_length<=5 && row2_length<=5)
									row_arr_prev = results_arr[row_num-1].gsub("\r","").split("\t") # Array of previous row

									if(row_arr_prev.push(*row_arr).join("\t") != previously_processed_row_arr.join("\t"))
										row_arr = row_arr.push(*row_arr2)
									else
										p "THIS ROW WAS ALREADY ADDED TO THE PREVIOUS ONE. SKIPPING..."
										next
									end # DONE: if(row_arr_prev.push(*row_arr) != previously_processed_row_arr)
								else
									p "BAD ROW, SKIPPING..."
									next
								end # DONE: if(row_length<=5 && row2_length<=5)
							end # DONE: if(row_length<=5)
						rescue Exception => e
							if(row_length>5)
								row_arr = row_arr
							else
								p "FINAL ROW IS BAD. SKIPPING..."
								break
							end
						end
						
						row_arr0_scan = row_arr[0].scan(/\([A-Z]{3}\)/)

						if(record_type==='CanLName')
							candidate = row_arr[0].gsub(/\'|\"/,"").gsub(/\(\w{3}\)/,'')
							candidate_party = row_arr0_scan[0]
							candidate_office = row_arr0_scan[1]
						else 
							committee = row_arr[0].gsub(/\'|\"/,"").gsub(/\(\w{3}\)/,'')
							committee_type = row_arr0_scan.length===1 ? row_arr0_scan[0] : row_arr0_scan[1] # Some committee names have two acornyms in parentheses, so in this case it's the second one which actually has the committee type
						end

						begin
							date_arr = row_arr[1].split('/')
							date = date_arr[-1]+'-'+date_arr[0]+'-'+date_arr[1]	#SQL date format						
						rescue Exception => e
							date = nil					
						end

						amount = row_arr[2]
						typ = row_arr[3]
						contributor_name = row_arr[4].gsub(/\'|\"/,"")
						
						address = row_arr[5]
						city_state_zip = row_arr[6]

						address_clean = nil
						city_state_zip_clean = nil
						po_box = nil

						# If the address is a PO box, we put the address string into the po_box column of our table
						if(address != nil)
							if(address.match(/p.*o.*\bbox\b/i).to_s.length > 1)
								po_box = address
							end
						end

						# If the city/state/zip string is a PO box, we put it in the po_box column of our table.
						# This overrides the above coding where we check the PO box ONLY IF BOTH ADDRESS AND CITY/STATE/ZIP STRINGS ARE P.O. BOXES
						if(city_state_zip != nil)
							if(city_state_zip.match(/p.*o.*\bbox\b/i).to_s.length > 1)
								po_box = city_state_zip
							end
						end

						# If a `city_state_zip` string has numbers in front of it, it's likely that it's actually a street address (e.g. "123 MAIN STREET, WEST PALM ").
						# In that case, we'll split it by comma...
						digits_front_cityStateZip_len = (city_state_zip===nil) ? nil : city_state_zip[0..4].match(/\d{2,}/).to_s.length
						if(digits_front_cityStateZip_len != nil)
							if(digits_front_cityStateZip_len > 1)
								csz_split = city_state_zip.split(',')

								# If the first part of `csz_split` has letters, it's likely an address, so we use that for `address_clean`. 
								# If there are no letter's, it's probably not an address, so we don't use it.
								address_clean = csz_split[0].match(/\w{2,}/).to_s.length> 1 ? csz_split[0] : nil 
								city_state_zip_clean = csz_split.length> 1 ? csz_split[-1] : nil
							end
							city_state_zip_clean = (city_state_zip_clean === nil) ? city_state_zip : city_state_zip_clean
						end

						if(city_state_zip_clean === nil)
							city = nil
							state = nil
							zip = nil
						else
							city = city_state_zip_clean.match(/^.*(?=\s\w{2}\s)/).to_s
							state = city_state_zip_clean.match(/\s\w{2}\s/).to_s
							zip = city_state_zip_clean.match(/\d{5}/).to_s
						end

						occupation = row_arr[7]

						if(occupation!=nil)
							# If the `occupation` string has five numbers and a space on the end of it, then it's likely a city, state and zip string
							if( occupation.reverse.match(/\d{5}\s/).to_s.length > 1 )
								# If the `occupation` string is a P.O. Box, just make the string `nil`, or else try to get the city, state and zip
								if( occupation.match(/p.*o.*\bbox\b/i).to_s.length > 1 )
									occupation = nil
								else
									occ_arr = occupation.split(',')
									city = (occ_arr[0] === nil) ? nil : occ_arr[0]
									state = (occ_arr[1] === nil) ? nil : occ_arr[1].match(/\w{2}/).to_s
									zip = (occ_arr[1] === nil) ? nil : occ_arr[1].match(/\d{5}/).to_s
								end
							end
						end

						if(address_clean === nil)
							address_clean = address
						end
						
						inkind_description = row_arr[8]

						scanned_arr = [
							election_value, 
							election_text, 
							candidate, 
							candidate_party, 
							candidate_office, 
							committee, 
							committee_type, 
							date, 
							amount, 
							typ, 
							contributor_name, 
							address, 
							address_clean,
							city_state_zip,
							city_state_zip_clean, 
							occupation, 
							inkind_description
						]

						cmpgn_contrib.insert(
							:elex_val => election_value.split('-')[0],
							:election_value => election_value,
							:election_text => election_text,
							:candidate => candidate,
							:candidate_party => candidate_party,
							:candidate_office => candidate_office,
							:committee => committee,
							:committee_type => committee_type,
							:date => date,
							:amount => amount,
							:typ => typ,
							:contributor_name => contributor_name,
							:address => address,
							:po_box => po_box,
							:city_state_zip => city_state_zip,
							:address_clean => address_clean,
							:city_state_zip_clean => city_state_zip_clean,
							:city => city,
							:state => state,
							:zip => zip,
							:occupation => occupation,
							:inkind_description => inkind_description
						)	

						p scanned_arr

						previously_processed_row_arr = row_arr
					} # DONE: (1..results_arr.length-1).each
				end
			}
		} 
	end
}