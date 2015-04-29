[
	'rubygems',
	'pp',
	'rest_client',
	'sequel'
].each{|g|
	require g
}

DB = Sequel.connect( 
	:adapter => 'mysql',
	:user=>ARGV[0], 
	:password=>ARGV[1], 
	:host=>ARGV[2],
	:database=>ARGV[3]
)

DB.create_table! :fl_cmte_list do 
	primary_key :row_id
	Integer :acctnum, :unique=>true, :null=>false
	String :name, :null=>false
	String :type, :null=>false
	String :type_desc, :null=>false
	String :addr1
	String :addr2
	String :city
	String :state
	String :zip
	String :county
	String :phone
	String :chair_last
	String :chair_first
	String :chair_mid
	String :treasurer_last
	String :treasurer_first
	String :treasurer_mid
end
fl_cmte_list = DB[:fl_cmte_list]

url = 'http://election.dos.state.fl.us/committees/extractComList.asp'
res = RestClient.post(url,{'FormSubmit'=>'Download'})
rows = res.split(/\r\n/)[1..-1]
rows.each{|row| 
	row_arr = row.split(/\t/)
	begin
		fl_cmte_list.insert(
			:acctnum => row_arr[0],
			:name => row_arr[1],
			:type => row_arr[2],
			:type_desc => row_arr[3],
			:addr1 => row_arr[4],
			:addr2 => row_arr[5],
			:city => row_arr[6],
			:state => row_arr[7],
			:zip => row_arr[8],
			:county => row_arr[9],
			:phone => row_arr[10],
			:chair_last => row_arr[11],
			:chair_first => row_arr[12],
			:chair_mid => row_arr[13],
			:treasurer_last => row_arr[14],
			:treasurer_first => row_arr[15],
			:treasurer_mid => row_arr[16]
		)	
		p row_arr		
	rescue Exception => e
		p "ERROR: #{e}"
		next
	end
}
